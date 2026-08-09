public extension StopPlace.Kind {

    /// Builds a kind from the feed that published a stop.
    ///
    /// A deliberate approximation. GTFS puts no mode on a stop — the only honest
    /// source is the `route_type` of the lines calling there, and that needs the
    /// `stop_times → trips → routes` join we have deferred. Until then the feed is
    /// the best available proxy, and it is wrong in exactly two known ways:
    /// the Staten Island Railway ships inside the subway feed and reads as subway,
    /// and NYC Ferry's shuttle-bus stops read as ferry.
    ///
    /// Mirrors the feed identifiers defined in `ZippNetworking`. Returns `nil` for
    /// a feed we do not recognise, so an unexpected one is skipped and logged
    /// rather than silently mislabelled as something it is not.
    ///
    /// - Parameters:
    ///   - ownPlatform: used by bus and ferry, where the stop *is* the boarding
    ///     point and no station sits above it.
    ///   - childPlatforms: used by subway and PATH, whose stations group them.
    static func make(
        feedID: String,
        ownPlatform: @autoclosure () -> Platform,
        childPlatforms: @autoclosure () -> [Platform]
    ) -> StopPlace.Kind? {
        if feedID.hasPrefix("bus") {
            return .bus(ownPlatform())
        }
        switch feedID {
        case "nyc-ferry": return .ferry(ownPlatform())
        case "subway": return .subway(childPlatforms())
        case "path": return .path(childPlatforms())
        default: return nil
        }
    }
}
