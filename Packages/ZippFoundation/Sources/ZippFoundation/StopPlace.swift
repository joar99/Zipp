import CoreLocation

/// How a stop relates to the physical world, mirroring GTFS `location_type`.
public enum StopPlaceKind: Int, Sendable, Codable, CaseIterable {
    /// A boardable location. In GTFS this is a blank or `0` `location_type`.
    case platform = 0
    /// A parent station grouping one or more platforms.
    case station = 1
    /// A street level entrance or exit belonging to a station.
    case entrance = 2
    /// A pathway node with no boarding of its own.
    case genericNode = 3
    /// A specific spot on a platform where riders board.
    case boardingArea = 4
}

/// A transit stop as the rest of the app understands it.
///
/// This is the value type that crosses module and concurrency boundaries. It is
/// deliberately free of both the wire format it was decoded from and the
/// persistence type it is stored as.
public struct StopPlace: Sendable, Hashable, Identifiable {

    /// The stop's identifier *within its own feed*. Not unique across feeds:
    /// several operators number their stops from scratch, so these do collide.
    public let stopID: String
    /// Which upstream feed this stop was sourced from.
    public let feedID: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let kind: StopPlaceKind
    /// The `stopID` of the station this stop belongs to, when it is a child.
    /// Always refers to a stop in the same feed.
    public let parentStationID: String?

    public init(
        stopID: String,
        feedID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kind: StopPlaceKind,
        parentStationID: String?
    ) {
        self.stopID = stopID
        self.feedID = feedID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.parentStationID = parentStationID
    }

    /// Unique across every feed, unlike ``stopID`` on its own.
    public var id: String { "\(feedID):\(stopID)" }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
