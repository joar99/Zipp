import SwiftData

/// The persisted form of a ``StopPlace``.
///
/// Instances stay bound to the `ModelContext` that created them, so they are
/// never handed across module boundaries. Callers exchange ``StopPlace`` values
/// instead and let the owning repository map between the two.
@Model
public final class StopPlaceEntity {

    // Feeds number their stops independently, so `stopID` alone is not unique:
    // constraining on it would make one operator's stop silently overwrite
    // another's during a save.
    #Unique<StopPlaceEntity>([\.feedID, \.stopID])
    #Index<StopPlaceEntity>([\.stopID], [\.feedID], [\.latitude, \.longitude])

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

    convenience init(stopPlace: StopPlace) {
        self.init(
            stopID: stopPlace.stopID,
            feedID: stopPlace.feedID,
            name: stopPlace.name,
            latitude: stopPlace.latitude,
            longitude: stopPlace.longitude,
            kindRawValue: stopPlace.kind.rawValue,
            parentStationID: stopPlace.parentStationID
        )
    }

    /// Copies incoming values onto an already persisted stop, leaving its
    /// identity intact.
    func update(from stopPlace: StopPlace) {
        name = stopPlace.name
        latitude = stopPlace.latitude
        longitude = stopPlace.longitude
        kindRawValue = stopPlace.kind.rawValue
        parentStationID = stopPlace.parentStationID
    }

    var stopPlace: StopPlace {
        StopPlace(
            stopID: stopID,
            feedID: feedID,
            name: name,
            latitude: latitude,
            longitude: longitude,
            kind: StopPlaceKind(rawValue: kindRawValue) ?? .platform,
            parentStationID: parentStationID
        )
    }
}
