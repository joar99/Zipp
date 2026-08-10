import Foundation
import OSLog
import SwiftData
import ZippFoundation
import ZippNetworking

private let logger = Logger(subsystem: "no.jonas.Zipp", category: "StopPlaceRepository")

/// Owns local storage of transit stops and keeps it in step with the published
/// feeds.
///
/// Storage is flat — one row per published stop — while callers receive assembled
/// ``StopPlace`` values. The two shapes serve different masters: feeds publish rows
/// and are merged row by row, but riders think in stop places.
///
/// Conformance to `ModelActor` is written by hand rather than using the
/// `@ModelActor` macro, because that macro generates an initialiser taking only a
/// container and leaves no room to inject the networking service.
public actor StopPlaceRepository: ModelActor, StopPlaceRepositoryProtocol {

    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    private let service: any StopPlaceServicing
    private let lineCatalogue: any LineCatalogueProtocol
    private let feeds: [GTFSFeed]

    /// Every platform in the dataset, keyed by its parent's qualified id.
    ///
    /// Held in memory because it is small, entirely static between refreshes, and
    /// needed by every single read. Rebuilding it per query cost ~30 ms whether the
    /// caller wanted 13 stops or 509 — three quarters of the time it took the map
    /// to settle. Invalidated by ``refresh(minimumInterval:)`` and nothing else.
    private var platformCache: [String: [Platform]]?

    public init(
        modelContainer: ModelContainer,
        service: any StopPlaceServicing = StopPlaceService(),
        lineCatalogue: any LineCatalogueProtocol = BundledLineCatalogue(),
        feeds: [GTFSFeed] = GTFSFeed.newYorkCity
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.service = service
        self.lineCatalogue = lineCatalogue
        self.feeds = feeds
    }
}

// MARK: - Reading

public extension StopPlaceRepository {

    /// Stop places within `bounds`, each assembled with its platforms.
    ///
    /// Only rows without a parent are returned. Child platforms share their
    /// station's exact coordinate, so drawing them would stack every one of them
    /// on a single pixel.
    func stopPlaces(in bounds: CoordinateBounds, limit: Int? = nil) throws -> [StopPlace] {
        let minimumLatitude = bounds.minimumLatitude
        let maximumLatitude = bounds.maximumLatitude
        let minimumLongitude = bounds.minimumLongitude
        let maximumLongitude = bounds.maximumLongitude

        var descriptor = FetchDescriptor<StopPlaceEntity>(
            predicate: #Predicate { entity in
                entity.parentStationID == nil
                    && entity.latitude >= minimumLatitude
                    && entity.latitude <= maximumLatitude
                    && entity.longitude >= minimumLongitude
                    && entity.longitude <= maximumLongitude
            }
        )
        descriptor.fetchLimit = limit
        return try assemble(modelContext.fetch(descriptor).map(\.record))
    }

    func stopPlace(id: String) throws -> StopPlace? {
        // The qualified identifier is `feed:stop`, and a stop identifier may itself
        // contain no colon, so splitting once from the left is unambiguous.
        let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let feedID = String(parts[0])
        let stopID = String(parts[1])

        var descriptor = FetchDescriptor<StopPlaceEntity>(
            predicate: #Predicate { $0.stopID == stopID && $0.feedID == feedID }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first?.record else { return nil }
        return try assemble([record]).first
    }

    func numberOfStopPlaces() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<StopPlaceEntity>())
    }
}

// MARK: - Assembling the facade

private extension StopPlaceRepository {

    /// Turns flat rows into ``StopPlace`` values, attaching each station's
    /// platforms.
    ///
    /// Platforms are fetched for all the given rows in one query rather than per
    /// stop, since the map asks for hundreds at a time.
    func assemble(_ records: [StopPlaceRecord]) throws -> [StopPlace] {
        let platformsByParent = try platformsByParentID()

        return records.compactMap { record in
            let kind = StopPlace.Kind.make(
                feedID: record.feedID,
                // Bus and ferry have no station layer, so the stop is its own
                // single platform — and its own line lookup key.
                ownPlatform: Platform(
                    id: record.id,
                    lines: lineCatalogue.lines(forPlatform: record.id)
                ),
                childPlatforms: platformsByParent[record.id] ?? []
            )
            guard let kind else {
                // Only reachable if a feed is added to the catalogue without
                // teaching `Kind` about it. Skipping beats guessing a mode.
                logger.error("Unrecognised feed \(record.feedID, privacy: .public); skipping stop \(record.id, privacy: .public)")
                return nil
            }
            return StopPlace(
                id: record.id,
                name: record.name,
                latitude: record.latitude,
                longitude: record.longitude,
                kind: kind
            )
        }
    }

    /// Every platform row, keyed by its parent's qualified id.
    ///
    /// Fetched wholesale rather than narrowed to the stops being assembled. Only
    /// subway and PATH have platforms at all — 1,021 rows across the entire
    /// dataset — so the whole set is cheaper than asking SwiftData to translate a
    /// predicate matching parent identifiers against a captured collection, which
    /// also required unwrapping an optional inside `#Predicate`.
    func platformsByParentID() throws -> [String: [Platform]] {
        if let platformCache { return platformCache }

        let children = try modelContext.fetch(
            FetchDescriptor<StopPlaceEntity>(
                predicate: #Predicate { $0.parentStationID != nil }
            )
        )

        var result: [String: [Platform]] = [:]
        for child in children {
            guard let parentStationID = child.parentStationID else { continue }
            // Both keys are qualified by feed: parent references only mean anything
            // inside their own feed, and the line catalogue is keyed the same way.
            let platformID = "\(child.feedID):\(child.stopID)"
            result["\(child.feedID):\(parentStationID)", default: []]
                .append(Platform(id: platformID, lines: lineCatalogue.lines(forPlatform: platformID)))
        }
        for key in result.keys {
            result[key]?.sort { $0.id < $1.id }
        }
        platformCache = result
        return result
    }
}

// MARK: - Refreshing

public extension StopPlaceRepository {

    @discardableResult
    func refresh(minimumInterval: TimeInterval) async -> StopPlaceSyncReport {
        let now = Date()
        let knownStates = (try? syncStatesByFeedID()) ?? [:]

        let dueFeeds = feeds.filter { feed in
            guard let state = knownStates[feed.id] else { return true }
            return now.timeIntervalSince(state.lastCheckedAt) >= minimumInterval
        }
        guard !dueFeeds.isEmpty else {
            logger.info("Refresh skipped, all \(self.feeds.count) feeds checked within the interval")
            return StopPlaceSyncReport(
                inserted: 0,
                updated: 0,
                removed: 0,
                unchangedFeeds: feeds.count,
                failedFeeds: []
            )
        }

        logger.info("Refreshing \(dueFeeds.count) of \(self.feeds.count) feeds")

        let results = await service.fetchStopPlaces(
            for: dueFeeds,
            cachedEntityTags: knownStates.compactMapValues(\.entityTag)
        )

        var counts = MergeCounts()
        var unchangedFeeds = feeds.count - dueFeeds.count
        var failedFeeds: [String] = []
        var touched: [FeedOutcome] = []

        for (feedID, result) in results {
            switch result {
            case .success(.unchanged):
                unchangedFeeds += 1
                logger.debug("\(feedID, privacy: .public): unchanged upstream")
                touched.append(FeedOutcome(feedID: feedID, entityTag: nil, didChange: false))

            case let .success(.updated(entityTag, records)):
                do {
                    let feedCounts = try merge(records, feedID: feedID)
                    counts.formUnion(feedCounts)
                    logger.info(
                        """
                        \(feedID, privacy: .public): \(records.count) stops fetched, \
                        +\(feedCounts.inserted) ~\(feedCounts.updated) -\(feedCounts.removed)
                        """
                    )
                    touched.append(
                        FeedOutcome(
                            feedID: feedID,
                            entityTag: entityTag,
                            didChange: feedCounts.didChange
                        )
                    )
                } catch {
                    logger.error("\(feedID, privacy: .public): merge failed, \(error, privacy: .public)")
                    failedFeeds.append(feedID)
                }

            case let .failure(error):
                logger.error("\(feedID, privacy: .public): fetch failed, \(error, privacy: .public)")
                failedFeeds.append(feedID)
            }
        }

        recordSyncStates(for: touched, at: now)

        do {
            try modelContext.save()
        } catch {
            logger.error("Saving refreshed stops failed, \(error, privacy: .public)")
        }

        // The only thing that can change the platform layout is a refresh that
        // actually touched rows, so this is the single invalidation point.
        if counts.didChange {
            platformCache = nil
        }

        let storedCount = (try? numberOfStopPlaces()) ?? -1
        logger.info(
            """
            Refresh finished: +\(counts.inserted) ~\(counts.updated) -\(counts.removed), \
            \(unchangedFeeds) feeds unchanged, \(failedFeeds.count) failed, \
            \(storedCount) stops stored
            """
        )

        return StopPlaceSyncReport(
            inserted: counts.inserted,
            updated: counts.updated,
            removed: counts.removed,
            unchangedFeeds: unchangedFeeds,
            failedFeeds: failedFeeds
        )
    }
}

// MARK: - Merging

private extension StopPlaceRepository {

    struct MergeCounts {
        var inserted = 0
        var updated = 0
        var removed = 0

        var didChange: Bool { inserted > 0 || updated > 0 || removed > 0 }

        mutating func formUnion(_ other: MergeCounts) {
            inserted += other.inserted
            updated += other.updated
            removed += other.removed
        }
    }

    struct FeedOutcome {
        let feedID: String
        let entityTag: String?
        let didChange: Bool
    }

    /// Reconciles one feed's rows against what is stored, touching only what
    /// actually differs.
    func merge(_ records: [StopPlaceRecord], feedID: String) throws -> MergeCounts {
        let stored = try modelContext.fetch(
            FetchDescriptor<StopPlaceEntity>(predicate: #Predicate { $0.feedID == feedID })
        )
        var storedByID = Dictionary(
            stored.map { ($0.stopID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var counts = MergeCounts()

        for record in records {
            if let entity = storedByID.removeValue(forKey: record.stopID) {
                // Only write when something differs, so an unchanged feed does not
                // dirty 16,000 rows.
                if entity.record != record {
                    entity.update(from: record)
                    counts.updated += 1
                }
            } else {
                modelContext.insert(StopPlaceEntity(record: record))
                counts.inserted += 1
            }
        }

        // Whatever is left was not in the feed any more.
        for orphan in storedByID.values {
            modelContext.delete(orphan)
            counts.removed += 1
        }

        return counts
    }
}

// MARK: - Sync bookkeeping

private extension StopPlaceRepository {

    func syncStatesByFeedID() throws -> [String: FeedSyncStateEntity] {
        let states = try modelContext.fetch(FetchDescriptor<FeedSyncStateEntity>())
        return Dictionary(states.map { ($0.feedID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func recordSyncStates(for outcomes: [FeedOutcome], at date: Date) {
        var states = (try? syncStatesByFeedID()) ?? [:]

        for outcome in outcomes {
            let state: FeedSyncStateEntity
            if let existing = states[outcome.feedID] {
                state = existing
            } else {
                state = FeedSyncStateEntity(feedID: outcome.feedID)
                modelContext.insert(state)
                states[outcome.feedID] = state
            }

            if let entityTag = outcome.entityTag {
                state.entityTag = entityTag
            }
            state.lastCheckedAt = date
            if outcome.didChange {
                state.lastUpdatedAt = date
            }
        }
    }
}
