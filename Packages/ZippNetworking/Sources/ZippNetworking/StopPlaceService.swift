import Foundation
import ZippFoundation

/// What a refresh attempt found upstream.
public enum StopPlaceFetchOutcome: Sendable {
    /// The feed is byte for byte what we already hold; nothing was transferred.
    case unchanged
    case updated(entityTag: String?, stopPlaces: [StopPlace])
}

public protocol StopPlaceServicing: Sendable {
    func fetchStopPlaces(
        for feed: GTFSFeed,
        cachedEntityTag: String?
    ) async throws -> StopPlaceFetchOutcome

    func fetchStopPlaces(
        for feeds: [GTFSFeed],
        cachedEntityTags: [String: String]
    ) async -> [String: Result<StopPlaceFetchOutcome, Error>]
}

/// Fetches transit stops from published GTFS archives.
public struct StopPlaceService: StopPlaceServicing {

    private let reader: RemoteZipReader

    public init(reader: RemoteZipReader = RemoteZipReader()) {
        self.reader = reader
    }

    public func fetchStopPlaces(
        for feed: GTFSFeed,
        cachedEntityTag: String?
    ) async throws -> StopPlaceFetchOutcome {
        // A HEAD first, rather than a conditional GET. `If-None-Match` would be
        // cheaper on a match, but on a miss the server sends the entire archive
        // and we lose the range optimisation below. HEAD costs one small round
        // trip and keeps the miss path just as narrow as the hit path.
        let entityTag = try await reader.entityTag(of: feed.url)
        if let entityTag, let cachedEntityTag, entityTag == cachedEntityTag {
            return .unchanged
        }

        let data = try await reader.data(forEntry: "stops.txt", in: feed.url)
        let stopPlaces = GTFSStopsDecoder.decode(data, feedID: feed.id)
        return .updated(entityTag: entityTag, stopPlaces: stopPlaces)
    }

    public func fetchStopPlaces(
        for feeds: [GTFSFeed],
        cachedEntityTags: [String: String]
    ) async -> [String: Result<StopPlaceFetchOutcome, Error>] {
        await withTaskGroup(
            of: (String, Result<StopPlaceFetchOutcome, Error>).self
        ) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let outcome = try await fetchStopPlaces(
                            for: feed,
                            cachedEntityTag: cachedEntityTags[feed.id]
                        )
                        return (feed.id, .success(outcome))
                    } catch {
                        // One operator being unreachable should not sink a refresh
                        // of the other eight.
                        return (feed.id, .failure(error))
                    }
                }
            }

            var results: [String: Result<StopPlaceFetchOutcome, Error>] = [:]
            for await (feedID, result) in group {
                results[feedID] = result
            }
            return results
        }
    }
}
