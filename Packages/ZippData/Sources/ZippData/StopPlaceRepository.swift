import Foundation
import OSLog
import SwiftData
import ZippFoundation
import ZippNetworking

private let logger = Logger(subsystem: "no.jonas.Zipp", category: "StopPlaceRepository")

/// Owns local storage of transit stops, and keeps it in step with the published
/// feeds.
///
/// Conformance to `ModelActor` is written out by hand rather than using the
/// `@ModelActor` macro, because the macro generates an initialiser that takes
/// only a container and leaves no room to inject the networking service.
public actor StopPlaceRepository: ModelActor, StopPlaceRepositoryProtocol {

    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    private let service: any StopPlaceServicing
    private let feeds: [GTFSFeed]

    public init(
        modelContainer: ModelContainer,
        service: any StopPlaceServicing = StopPlaceService(),
        feeds: [GTFSFeed] = GTFSFeed.newYorkCity
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.service = service
        self.feeds = feeds
    }
}

// MARK: - Reading

public extension StopPlaceRepository {

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
        return try modelContext.fetch(descriptor).map(\.stopPlace)
    }

    func platforms(of station: StopPlace) throws -> [StopPlace] {
        let stationID = station.stopID
        let feedID = station.feedID
        let descriptor = FetchDescriptor<StopPlaceEntity>(
            predicate: #Predicate { entity in
                entity.parentStationID == stationID && entity.feedID == feedID
            },
            sortBy: [SortDescriptor(\.stopID)]
        )
        return try modelContext.fetch(descriptor).map(\.stopPlace)
    }

    func stopPlace(stopID: String, feedID: String) throws -> StopPlace? {
        var descriptor = FetchDescriptor<StopPlaceEntity>(
            predicate: #Predicate { entity in
                entity.stopID == stopID && entity.feedID == feedID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.stopPlace
    }

    func numberOfStopPlaces() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<StopPlaceEntity>())
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

            case let .success(.updated(entityTag, stopPlaces)):
                do {
                    let feedCounts = try merge(stopPlaces, feedID: feedID)
                    counts.formUnion(feedCounts)
                    logger.info(
                        """
                        \(feedID, privacy: .public): \(stopPlaces.count) stops fetched, \
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

    /// Reconciles one feed's stops against what is already stored, touching only
    /// the rows that actually differ.
    func merge(_ stopPlaces: [StopPlace], feedID: String) throws -> MergeCounts {
        let stored = try modelContext.fetch(
            FetchDescriptor<StopPlaceEntity>(predicate: #Predicate { $0.feedID == feedID })
        )
        var storedByID = Dictionary(
            stored.map { ($0.stopID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var counts = MergeCounts()

        for stopPlace in stopPlaces {
            if let entity = storedByID.removeValue(forKey: stopPlace.stopID) {
                // Only write when something actually differs, so an unchanged
                // feed does not dirty 16,000 rows.
                if entity.stopPlace != stopPlace {
                    entity.update(from: stopPlace)
                    counts.updated += 1
                }
            } else {
                modelContext.insert(StopPlaceEntity(stopPlace: stopPlace))
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
