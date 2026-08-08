import Foundation

/// One upstream GTFS archive.
///
/// New York has no single combined feed, so a full picture of the city means
/// aggregating a handful of per-operator and per-borough archives.
public struct GTFSFeed: Sendable, Hashable, Identifiable {

    public let id: String
    public let displayName: String
    public let url: URL

    public init(id: String, displayName: String, url: URL) {
        self.id = id
        self.displayName = displayName
        self.url = url
    }
}

public extension GTFSFeed {

    private static func mta(_ id: String, _ name: String, _ file: String) -> GTFSFeed {
        GTFSFeed(
            id: id,
            displayName: name,
            url: URL(string: "https://rrgtfsfeeds.s3.amazonaws.com/\(file).zip")!
        )
    }

    /// Also carries the Staten Island Railway.
    static let subway = mta("subway", "Subway", "gtfs_subway")
    static let busBronx = mta("bus-bronx", "Bronx Bus", "gtfs_bx")
    static let busBrooklyn = mta("bus-brooklyn", "Brooklyn Bus", "gtfs_b")
    static let busManhattan = mta("bus-manhattan", "Manhattan Bus", "gtfs_m")
    static let busQueens = mta("bus-queens", "Queens Bus", "gtfs_q")
    static let busStatenIsland = mta("bus-staten-island", "Staten Island Bus", "gtfs_si")
    static let busCompany = mta("bus-company", "MTA Bus Company", "gtfs_busco")

    static let ferry = GTFSFeed(
        id: "nyc-ferry",
        displayName: "NYC Ferry",
        url: URL(string: "https://nycferry.connexionz.net/rtt/public/utility/gtfs.aspx")!
    )

    static let path = GTFSFeed(
        id: "path",
        displayName: "PATH",
        url: URL(string: "https://data.trilliumtransit.com/gtfs/path-nj-us/path-nj-us.zip")!
    )

    /// Every feed that serves New York City itself.
    ///
    /// Long Island Rail Road and Metro-North are deliberately absent: they are
    /// commuter rail whose stops are overwhelmingly outside the five boroughs.
    static let newYorkCity: [GTFSFeed] = [
        .subway,
        .busBronx,
        .busBrooklyn,
        .busManhattan,
        .busQueens,
        .busStatenIsland,
        .busCompany,
        .ferry,
        .path,
    ]
}
