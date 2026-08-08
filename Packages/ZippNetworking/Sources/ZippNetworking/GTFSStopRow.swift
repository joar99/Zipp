import CoreLocation
import Foundation
import ZippFoundation

/// One row of a GTFS `stops.txt`, in the shape the feed publishes it.
///
/// Intentionally not `public`: the wire format stops at this module's boundary,
/// and callers only ever see the ``StopPlace`` it maps to.
struct GTFSStopRow: Sendable {
    let stopID: String
    let stopName: String
    let stopLatitude: String
    let stopLongitude: String
    let locationType: String
    let parentStation: String
}

extension GTFSStopRow {

    /// Maps a feed row onto the app's own model, discarding rows that cannot
    /// be placed on a map.
    func stopPlace(feedID: String) -> StopPlace? {
        guard !stopID.isEmpty,
              let latitude = Double(stopLatitude),
              let longitude = Double(stopLongitude),
              CLLocationCoordinate2DIsValid(
                  CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
              )
        else { return nil }

        // GTFS leaves `location_type` blank for ordinary boardable stops.
        let kind = StopPlaceKind(rawValue: Int(locationType) ?? 0) ?? .platform

        return StopPlace(
            stopID: stopID,
            feedID: feedID,
            name: stopName,
            latitude: latitude,
            longitude: longitude,
            kind: kind,
            parentStationID: parentStation.isEmpty ? nil : parentStation
        )
    }
}

/// Turns the bytes of a `stops.txt` into model values.
enum GTFSStopsDecoder {

    static func decode(_ data: Data, feedID: String) -> [StopPlace] {
        let text = String(decoding: data, as: UTF8.self)
        var rows = DelimitedTextParser.rows(from: text)[...]

        guard let header = rows.popFirst() else { return [] }
        // Column order is not guaranteed by the spec, so bind by name.
        let columns = Dictionary(
            header.enumerated().map { index, name in
                (name.trimmingCharacters(in: .whitespaces), index)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Feeds pad their values inconsistently: the subway feed writes
        // `40.872562` while the bus feeds write `  40.872562`, and `Double.init`
        // rejects the latter outright.
        func value(_ fields: [String], _ column: String) -> String {
            guard let index = columns[column], index < fields.count else { return "" }
            return fields[index].trimmingCharacters(in: .whitespaces)
        }

        return rows.compactMap { fields in
            GTFSStopRow(
                stopID: value(fields, "stop_id"),
                stopName: value(fields, "stop_name"),
                stopLatitude: value(fields, "stop_lat"),
                stopLongitude: value(fields, "stop_lon"),
                locationType: value(fields, "location_type"),
                parentStation: value(fields, "parent_station")
            )
            .stopPlace(feedID: feedID)
        }
    }
}
