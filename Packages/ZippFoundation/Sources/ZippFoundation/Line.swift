/// A service calling at a platform — the "1", the "M104", the ferry's East River
/// route.
///
/// GTFS calls these routes. Riders call them lines, and so does the rest of this
/// app.
public struct Line: Sendable, Hashable, Identifiable {

    /// Qualified as `feed:route`, since route identifiers are only unique within
    /// the feed that published them.
    public let id: String
    /// What goes on the badge: `1`, `M104`, `PATH`.
    public let name: String
    /// The full description: `Broadway - 7 Avenue Local`. Worth showing when
    /// ``name`` alone does not distinguish one service from another — every PATH
    /// route is called "PATH", and only this tells them apart.
    public let longName: String
    /// `RRGGBB`, as published. MTA supplies official colours for every route.
    public let colorHex: String

    public init(id: String, name: String, longName: String, colorHex: String) {
        self.id = id
        self.name = name
        self.longName = longName
        self.colorHex = colorHex
    }
}
