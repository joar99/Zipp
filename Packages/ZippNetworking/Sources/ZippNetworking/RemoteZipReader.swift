import Foundation

/// Reads a single entry out of a remote ZIP archive without downloading the
/// whole file.
///
/// A ZIP keeps its table of contents at the end of the archive, so with HTTP
/// range requests we can fetch the trailer, look up exactly where one entry
/// lives, and pull only those bytes. For the MTA GTFS feeds this is the
/// difference between transferring ~52 MB of archives and under 1 MB, since
/// `stops.txt` is a rounding error next to the `stop_times.txt` sitting beside
/// it in the same archive.
public struct RemoteZipReader: Sendable {

    public enum Failure: Error, Sendable {
        case missingContentLength
        case rangeRequestsUnsupported
        case endOfCentralDirectoryNotFound
        case entryNotFound(String)
        case unsupportedCompressionMethod(UInt16)
        case zip64Unsupported
        case malformedArchive
        case unexpectedStatusCode(Int)
    }

    /// Largest possible end-of-central-directory record: 22 byte fixed portion
    /// plus a comment field that tops out at 65,535 bytes.
    private static let maximumTrailerLength = 65_557

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The current entity tag for `url`, used to detect that a feed changed
    /// without transferring any of its body.
    public func entityTag(of url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.malformedArchive }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.unexpectedStatusCode(http.statusCode)
        }
        return http.value(forHTTPHeaderField: "ETag")
    }

    /// Downloads and inflates a single named entry from the archive at `url`.
    public func data(forEntry entryName: String, in url: URL) async throws -> Data {
        let totalLength = try await contentLength(of: url)

        let trailerLength = min(Self.maximumTrailerLength, totalLength)
        let trailerStart = totalLength - trailerLength
        let trailer = try await bytes(of: url, from: trailerStart, to: totalLength - 1)

        let directory = try await centralDirectory(
            url: url,
            trailer: trailer,
            trailerStart: trailerStart
        )
        let entry = try locate(entryName: entryName, in: directory)

        // The central directory records where the *local* header starts, but the
        // payload sits past that header's own variable length name and extra
        // fields, so we read those lengths before asking for the payload.
        let localHeader = try await bytes(
            of: url,
            from: entry.localHeaderOffset,
            to: entry.localHeaderOffset + 29
        )
        guard localHeader.count >= 30 else { throw Failure.malformedArchive }
        let nameLength = Int(readUInt16(localHeader, at: 26))
        let extraLength = Int(readUInt16(localHeader, at: 28))
        let payloadStart = entry.localHeaderOffset + 30 + nameLength + extraLength

        let payload = try await bytes(
            of: url,
            from: payloadStart,
            to: payloadStart + entry.compressedSize - 1
        )
        return try inflate(payload, method: entry.compressionMethod)
    }
}

// MARK: - Archive structure

private extension RemoteZipReader {

    struct Entry {
        let compressionMethod: UInt16
        let compressedSize: Int
        let localHeaderOffset: Int
    }

    static let centralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
    static let endOfCentralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]

    func centralDirectory(url: URL, trailer: [UInt8], trailerStart: Int) async throws -> [UInt8] {
        guard let signatureIndex = lastIndex(of: Self.endOfCentralDirectorySignature, in: trailer) else {
            throw Failure.endOfCentralDirectoryNotFound
        }
        guard signatureIndex + 20 <= trailer.count else { throw Failure.malformedArchive }

        let directorySize = Int(readUInt32(trailer, at: signatureIndex + 12))
        let directoryOffset = Int(readUInt32(trailer, at: signatureIndex + 16))

        // 0xFFFFFFFF in either field means the real values live in a ZIP64
        // record. None of the GTFS feeds are anywhere near the 4 GB that would
        // require, so this is treated as unsupported rather than handled.
        guard directorySize != Int(UInt32.max), directoryOffset != Int(UInt32.max) else {
            throw Failure.zip64Unsupported
        }

        // The directory is often already inside the trailer we fetched.
        if directoryOffset >= trailerStart {
            let start = directoryOffset - trailerStart
            let end = start + directorySize
            guard end <= trailer.count else { throw Failure.malformedArchive }
            return Array(trailer[start..<end])
        }
        return try await bytes(of: url, from: directoryOffset, to: directoryOffset + directorySize - 1)
    }

    func locate(entryName: String, in directory: [UInt8]) throws -> Entry {
        var offset = 0
        while offset + 46 <= directory.count {
            guard Array(directory[offset..<offset + 4]) == Self.centralDirectorySignature else {
                break
            }
            let compressionMethod = readUInt16(directory, at: offset + 10)
            let compressedSize = Int(readUInt32(directory, at: offset + 20))
            let nameLength = Int(readUInt16(directory, at: offset + 28))
            let extraLength = Int(readUInt16(directory, at: offset + 30))
            let commentLength = Int(readUInt16(directory, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(directory, at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= directory.count else { throw Failure.malformedArchive }
            let name = String(decoding: directory[nameStart..<nameStart + nameLength], as: UTF8.self)

            if name == entryName {
                return Entry(
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            }
            offset = nameStart + nameLength + extraLength + commentLength
        }
        throw Failure.entryNotFound(entryName)
    }

    func inflate(_ payload: [UInt8], method: UInt16) throws -> Data {
        switch method {
        case 0: // stored
            return Data(payload)
        case 8: // deflate
            // Apple's `.zlib` algorithm is raw DEFLATE with no wrapper, which is
            // exactly how ZIP stores its payloads.
            return try (Data(payload) as NSData).decompressed(using: .zlib) as Data
        default:
            throw Failure.unsupportedCompressionMethod(method)
        }
    }
}

// MARK: - Transport

private extension RemoteZipReader {

    func contentLength(of url: URL) async throws -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.malformedArchive }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.unexpectedStatusCode(http.statusCode)
        }
        guard http.expectedContentLength > 0 else { throw Failure.missingContentLength }
        return Int(http.expectedContentLength)
    }

    func bytes(of url: URL, from start: Int, to end: Int) async throws -> [UInt8] {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.malformedArchive }
        // A 200 here means the server ignored the range and sent the whole file,
        // which defeats the entire point of this reader.
        guard http.statusCode != 200 else { throw Failure.rangeRequestsUnsupported }
        guard http.statusCode == 206 else { throw Failure.unexpectedStatusCode(http.statusCode) }
        return [UInt8](data)
    }
}

// MARK: - Byte reading

private extension RemoteZipReader {

    func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    func lastIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= pattern.count else { return nil }
        var index = bytes.count - pattern.count
        while index >= 0 {
            if Array(bytes[index..<index + pattern.count]) == pattern { return index }
            index -= 1
        }
        return nil
    }
}
