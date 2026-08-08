/// A way of travelling that serves a stop.
public enum TransportMode: String, Sendable, Hashable, CaseIterable, Codable {
    case subway
    case bus
    case ferry
    case rail
    case tram
    case other
}

public extension StopPlace {

    /// The modes served here.
    ///
    /// Modelled as a set because a place is *served by* modes rather than being
    /// one, and real stops genuinely serve several. Today it is always derived
    /// from the feed and so holds a single value; establishing the plural shape
    /// now means the callers and the UI need not change when the real
    /// `stop_times → trips → routes` join eventually populates it properly.
    var modes: Set<TransportMode> {
        [TransportMode(feedID: feedID)]
    }
}

extension TransportMode {

    /// Infers a mode from the feed that published a stop.
    ///
    /// A deliberate approximation, and mirrors the feed catalogue in
    /// `ZippNetworking`. GTFS feeds are not mode-pure: the subway feed also
    /// carries the Staten Island Railway, and the ferry feed carries the shuttle
    /// buses that connect its landings. Those stops are labelled by their feed's
    /// dominant mode until a real route join is available.
    init(feedID: String) {
        if feedID.hasPrefix("bus") {
            self = .bus
        } else {
            switch feedID {
            case "subway": self = .subway
            case "nyc-ferry": self = .ferry
            case "path": self = .rail
            default: self = .other
            }
        }
    }
}
