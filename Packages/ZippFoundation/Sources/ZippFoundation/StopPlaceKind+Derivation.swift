public extension StopPlace.Kind {

    /// Builds a kind from what the lines calling at a stop say they are.
    ///
    /// The mode comes from the operators' published `route_type` and from nothing
    /// else. It deliberately does **not** fall back to the feed a stop arrived in,
    /// even though the feed guesses right slightly more often (42 stops to 25 across
    /// the 15,405 in the dataset). Mixing the two would mean a rule per feed, kept by
    /// hand, forever — and the feed is only ever right by accident.
    ///
    /// The consequence, which is intended: a stop no scheduled trip visits has no
    /// `route_type` to read, so it gets no kind and is dropped by the caller.
    ///
    /// The mode is taken from the first line that states one rather than reconciled
    /// across them all. That is not a shortcut — no platform in the dataset serves
    /// more than one `route_type`, verified across all 15,405 — so there is nothing
    /// to reconcile.
    ///
    /// - Parameters:
    ///   - ownPlatform: the stop as its own boarding point, for bus and ferry. An
    ///     autoclosure because building it costs a catalogue lookup that a station
    ///     never needs.
    ///   - childPlatforms: the directions grouped under a station.
    /// - Returns: `nil` when nothing scheduled calls at the stop.
    static func make(
        ownPlatform: @autoclosure () -> Platform,
        childPlatforms: @autoclosure () -> [Platform]
    ) -> StopPlace.Kind? {
        let children = childPlatforms()

        // Lines hang off platforms and never off a station — all 565,093 `stop_times`
        // references point at one — so a station's mode is its children's. Only a
        // stop with no children is its own platform and carries them directly.
        if let mode = children.lazy.flatMap(\.lines).compactMap(\.mode).first {
            return make(mode: mode, ownPlatform: ownPlatform(), childPlatforms: children)
        }

        let own = ownPlatform()
        guard let mode = own.lines.lazy.compactMap(\.mode).first else { return nil }
        return make(mode: mode, ownPlatform: own, childPlatforms: children)
    }
}

private extension StopPlace.Kind {

    /// Pairs a mode with the platform shape it implies.
    ///
    /// Which shape is not a second guess: bus and ferry stops have no children in any
    /// feed, and subway and rail stations always do.
    static func make(
        mode: TransportMode,
        ownPlatform: @autoclosure () -> Platform,
        childPlatforms: [Platform]
    ) -> StopPlace.Kind {
        switch mode {
        case .subway: .subway(childPlatforms)
        case .rail: .rail(childPlatforms)
        case .bus: .bus(ownPlatform())
        case .ferry: .ferry(ownPlatform())
        }
    }
}
