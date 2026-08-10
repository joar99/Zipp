import Foundation
import OSLog

private let logger = Logger(subsystem: "no.jonas.Zipp", category: "LineCatalogue")

/// Which lines call at which platform.
///
/// GTFS states this nowhere. The only path from a stop to its routes runs through
/// `stop_times`, which is 416 MB uncompressed across the NYC feeds — too much to
/// ship and far too much to parse on a phone. So `Tools/generate_lines.py` performs
/// the join at build time and this reads the few hundred KB of answers.
///
/// Regenerate whenever the feeds change materially:
///
///     python3 Tools/generate_lines.py
public protocol LineCatalogueProtocol: Sendable {
    /// Lines calling at a platform, in the order they should be shown.
    /// Empty for a station — stations are not referenced by `stop_times`, so their
    /// lines are the union of their platforms'.
    func lines(forPlatform platformID: String) -> [Line]
}

/// Reads the generated mapping out of the bundle.
///
/// Parsing is deferred to first use rather than done at init: it is a few hundred
/// KB of JSON, and nothing needs it until a rider taps something.
public final class BundledLineCatalogue: LineCatalogueProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: Storage?

    public init() {}

    public func lines(forPlatform platformID: String) -> [Line] {
        lock.lock()
        defer { lock.unlock() }

        let storage = loadIfNeeded()
        return (storage.platforms[platformID] ?? []).compactMap { storage.lines[$0] }
    }
}

private extension BundledLineCatalogue {

    struct Storage {
        var lines: [String: Line] = [:]
        var platforms: [String: [String]] = [:]
    }

    /// Mirrors the generator's output. Keys are single characters because the file
    /// carries 15,000 platforms and the names would otherwise dominate its size.
    struct Payload: Decodable {
        struct Route: Decodable {
            let n: String
            let c: String
            let l: String
            /// `route_type`, kept as the raw integer so an unrecognised one survives
            /// decoding and is dropped deliberately rather than failing the whole file.
            let t: Int
        }
        let lines: [String: Route]
        let platforms: [String: [String]]
    }

    func loadIfNeeded() -> Storage {
        if let storage { return storage }

        let loaded = Self.load()
        storage = loaded
        return loaded
    }

    static func load() -> Storage {
        guard let url = Bundle.module.url(forResource: "Lines", withExtension: "json") else {
            logger.error("Lines.json missing from the bundle; no line will ever be shown")
            return Storage()
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
            var storage = Storage()
            storage.platforms = payload.platforms
            // The identifier is the dictionary key, so it is folded in here rather
            // than repeated inside every entry in the file.
            storage.lines = payload.lines.reduce(into: [:]) { result, entry in
                result[entry.key] = Line(
                    id: entry.key,
                    name: entry.value.n,
                    longName: entry.value.l,
                    colorHex: entry.value.c,
                    mode: TransportMode(rawValue: entry.value.t)
                )
            }
            logger.info("Loaded \(storage.lines.count) lines across \(storage.platforms.count) platforms")
            return storage
        } catch {
            logger.error("Could not read Lines.json, \(error, privacy: .public)")
            return Storage()
        }
    }
}
