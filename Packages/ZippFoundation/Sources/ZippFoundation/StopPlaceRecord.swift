/// One stop exactly as a feed published it, before any hierarchy is assembled.
///
/// This is the flat, `Sendable` value that crosses module and concurrency
/// boundaries — networking decodes into it, and the repository stores it and later
/// assembles ``StopPlace`` values from it. Kept separate from the facade for two
/// reasons: SwiftData models stay bound to the context that created them and so
/// cannot travel, and storing the tree rather than the rows would fight both the
/// store and the incremental merge.
public struct StopPlaceRecord: Sendable, Hashable, Identifiable {

    /// The identifier the publisher assigned. Only unique *within* its feed —
    /// 686 stops are published twice by overlapping bus feeds, and identifiers
    /// coincide between unrelated operators.
    public let stopID: String
    /// Which feed this came from. Also, for now, how the mode is inferred.
    public let feedID: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let kind: Kind
    /// The `stopID` of the station this belongs to, if it is a child. Always
    /// refers to a stop in the same feed.
    public let parentStationID: String?

    public init(
        stopID: String,
        feedID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kind: Kind,
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

    /// Unique across every feed, unlike ``stopID`` alone.
    public var id: String { "\(feedID):\(stopID)" }
}

public extension StopPlaceRecord {

    /// What the publisher says this row is, mirroring GTFS `location_type`.
    ///
    /// Only `platform` and `station` occur in the NYC feeds, plus `entrance` in
    /// PATH — the sole publisher of any. The remaining cases exist so an
    /// unexpected feed decodes rather than failing.
    enum Kind: Int, Sendable, Codable, CaseIterable {
        /// A boardable location. Blank or `0` in GTFS.
        case platform = 0
        /// A parent grouping one or more platforms.
        case station = 1
        /// A street level way in. PATH publishes 22; nobody else publishes any.
        case entrance = 2
        case genericNode = 3
        case boardingArea = 4
    }
}
