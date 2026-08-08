import CoreLocation

/// A rectangular slice of the world, used to ask for only the stops currently
/// worth drawing.
public struct CoordinateBounds: Sendable, Hashable {

    public let minimumLatitude: Double
    public let maximumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLongitude: Double

    public init(
        minimumLatitude: Double,
        maximumLatitude: Double,
        minimumLongitude: Double,
        maximumLongitude: Double
    ) {
        self.minimumLatitude = minimumLatitude
        self.maximumLatitude = maximumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLongitude = maximumLongitude
    }
}

/// What a refresh pass did.
public struct StopPlaceSyncReport: Sendable, Hashable {
    public let inserted: Int
    public let updated: Int
    public let removed: Int
    public let unchangedFeeds: Int
    public let failedFeeds: [String]

    public init(
        inserted: Int,
        updated: Int,
        removed: Int,
        unchangedFeeds: Int,
        failedFeeds: [String]
    ) {
        self.inserted = inserted
        self.updated = updated
        self.removed = removed
        self.unchangedFeeds = unchangedFeeds
        self.failedFeeds = failedFeeds
    }

    public var didChangeAnything: Bool {
        inserted > 0 || updated > 0 || removed > 0
    }
}

public protocol StopPlaceRepositoryProtocol: Sendable {

    /// Stops that can be drawn as their own pin, within `bounds`.
    ///
    /// Child platforms are excluded: they share a coordinate with their parent
    /// station and would stack pins on top of each other.
    func stopPlaces(in bounds: CoordinateBounds, limit: Int?) async throws -> [StopPlace]

    /// The platforms belonging to a station, for when a rider taps it.
    ///
    /// Scoped to the station's own feed, since `parent_station` references are
    /// only meaningful within the feed that published them.
    func platforms(of station: StopPlace) async throws -> [StopPlace]

    func stopPlace(stopID: String, feedID: String) async throws -> StopPlace?

    func numberOfStopPlaces() async throws -> Int

    /// Brings local storage in line with the published feeds, skipping any feed
    /// checked more recently than `minimumInterval`.
    @discardableResult
    func refresh(minimumInterval: TimeInterval) async -> StopPlaceSyncReport
}

public extension StopPlaceRepositoryProtocol {

    /// One week. Stop locations move rarely enough that checking more often
    /// spends bandwidth without finding anything.
    static var defaultRefreshInterval: TimeInterval { 60 * 60 * 24 * 7 }

    func stopPlaces(in bounds: CoordinateBounds) async throws -> [StopPlace] {
        try await stopPlaces(in: bounds, limit: nil)
    }

    @discardableResult
    func refresh() async -> StopPlaceSyncReport {
        await refresh(minimumInterval: Self.defaultRefreshInterval)
    }
}
