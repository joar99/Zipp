import CoreLocation

/// A place a rider walks to and departs from — the thing we draw on the map.
///
/// What that *is* differs by mode, and the asymmetry comes from the data rather
/// than from us: subway and PATH publish a station grouping several platforms,
/// while bus and ferry publish the boarding point directly with no station layer
/// above it. ``Kind`` carries that difference.
///
/// Deliberately not modelled here:
/// - **Station complexes.** GTFS allows one level of `parent_station`, so what it
///   calls a station is really one group of lines — Times Square is four of them,
///   spread over 293 metres. The grouping lives in `transfers.txt`, but a complex
///   has no name and half of them have members that disagree, so there is nothing
///   to call the result.
/// - **Several modes per stop.** A full route join found no stop serving more than
///   one `route_type`, so ``Kind`` is singular rather than a set.
public struct StopPlace: Sendable, Hashable, Identifiable {

    /// Unique across every feed. Stop identifiers are only unique *within* a feed,
    /// so this is qualified by whoever published it.
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let kind: Kind

    public init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kind: Kind
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public extension StopPlace {

    /// How a stop place is structured, which follows from who published it.
    ///
    /// An enum so that adding an operator fails to compile until it is handled
    /// everywhere, and so "a bus stop with no platforms" cannot be expressed: bus
    /// and ferry take exactly one platform rather than an array.
    ///
    /// The array cases are never empty in practice — every station has platforms,
    /// subway exactly two and PATH two to four, none with zero.
    enum Kind: Sendable, Hashable {
        /// The stop *is* the boarding point; nothing sits above it.
        case bus(Platform)
        case ferry(Platform)
        /// A station whose platforms are its directions.
        case subway([Platform])
        case path([Platform])
    }
}

public extension StopPlace.Kind {

    /// Uniform access for callers that do not care how a stop is structured.
    var platforms: [Platform] {
        switch self {
        case let .bus(platform), let .ferry(platform):
            [platform]
        case let .subway(platforms), let .path(platforms):
            platforms
        }
    }
}

/// A direction within a stop place, and what lines attach to.
///
/// Carries neither coordinate nor name, which is not an omission: all 1,021
/// platforms in the NYC feeds sit at their station's *exact* coordinate and carry a
/// name byte-identical to it. Storing either would be inventing data.
///
/// The type earns its place because every one of the 565,093 `stop_times`
/// references points at a platform and none at a station. `101N` means "the
/// northbound side", which is where lines and departures will hang once that join
/// exists.
public struct Platform: Sendable, Hashable, Identifiable {

    /// Qualified as `feed:stop`, matching the keys the line catalogue is built on.
    public let id: String
    /// The services calling here. Empty only where a feed publishes a platform no
    /// scheduled trip ever visits — three exist in the subway feed.
    public let lines: [Line]

    public init(id: String, lines: [Line] = []) {
        self.id = id
        self.lines = lines
    }
}
