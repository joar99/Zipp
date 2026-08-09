import SwiftData

/// The persisted form of a ``StopPlaceRecord``.
///
/// Storage is **flat**, mirroring how GTFS publishes it, rather than storing the
/// assembled ``StopPlace`` tree. Rows arrive flat from the feeds and are merged
/// row by row, so keeping them that way lets the incremental merge touch only what
/// changed; the hierarchy is assembled on read instead.
///
/// Instances stay bound to the `ModelContext` that created them, so they never
/// leave the repository. Callers exchange ``StopPlaceRecord`` and ``StopPlace``.
@Model
public final class StopPlaceEntity {

    // Feeds number their stops independently, so `stopID` alone is not unique —
    // constraining on it made one operator's stop silently overwrite another's
    // during a save, losing rows without an error.
    #Unique<StopPlaceEntity>([\.feedID, \.stopID])
    #Index<StopPlaceEntity>([\.stopID], [\.feedID], [\.parentStationID], [\.latitude, \.longitude])

    public var stopID: String
    public var feedID: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var kindRawValue: Int
    public var parentStationID: String?

    public init(
        stopID: String,
        feedID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kindRawValue: Int,
        parentStationID: String?
    ) {
        self.stopID = stopID
        self.feedID = feedID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.kindRawValue = kindRawValue
        self.parentStationID = parentStationID
    }
}

public extension StopPlaceEntity {

    convenience init(record: StopPlaceRecord) {
        self.init(
            stopID: record.stopID,
            feedID: record.feedID,
            name: record.name,
            latitude: record.latitude,
            longitude: record.longitude,
            kindRawValue: record.kind.rawValue,
            parentStationID: record.parentStationID
        )
    }

    /// Copies incoming values onto an already stored row, leaving its identity
    /// intact so the merge does not churn the store.
    func update(from record: StopPlaceRecord) {
        name = record.name
        latitude = record.latitude
        longitude = record.longitude
        kindRawValue = record.kind.rawValue
        parentStationID = record.parentStationID
    }

    var record: StopPlaceRecord {
        StopPlaceRecord(
            stopID: stopID,
            feedID: feedID,
            name: name,
            latitude: latitude,
            longitude: longitude,
            kind: StopPlaceRecord.Kind(rawValue: kindRawValue) ?? .platform,
            parentStationID: parentStationID
        )
    }
}
