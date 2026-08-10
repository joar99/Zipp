/// What a rider boards.
///
/// GTFS states this on the *route*, as `route_type`, and nowhere on the stop. That
/// is the whole reason deriving a stop's mode needs the line catalogue rather than
/// just the stop row.
///
/// These four are what the nine NYC feeds actually publish. The rest of the GTFS
/// enumeration — tram, cable car, the extended 7xx range — never appears, so
/// modelling it would be modelling nothing. Anything else decodes to `nil` rather
/// than to a guess.
public enum TransportMode: Int, Sendable, Hashable, CaseIterable {
    case subway = 1
    /// PATH *and* the Staten Island Railway. Both publish `route_type` 2, so the
    /// feeds draw no distinction between them, and neither do we.
    ///
    /// Both are really metros rather than commuter rail, so this label is arguably
    /// wrong for both — but it is the operators' own, it is the only one they
    /// publish, and theirs is the copy that can be corrected. See the mode
    /// discussion in CLAUDE.md.
    case rail = 2
    case bus = 3
    case ferry = 4
}
