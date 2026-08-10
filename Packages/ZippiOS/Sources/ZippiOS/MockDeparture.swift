import SwiftUI
import ZippFoundation

/// MOCK DATA — departures only. Lines are real now, derived from the feeds at
/// build time by `Tools/generate_lines.py`.
///
/// Real departures are *live* data and cannot be bundled: MTA publishes
/// GTFS-Realtime protobuf for subway (no API key, but one feed per line group,
/// filtered client-side) and SIRI `StopMonitoring` for bus (per stop, but needs a
/// key). Until that exists, these are invented.
struct MockDeparture: Identifiable, Hashable {
    let id: String
    let minutesAway: Int

    var label: String {
        minutesAway == 0 ? "Now" : "\(minutesAway) min"
    }
}

extension Platform {

    /// Subway platform identifiers end in a direction letter (`101N`, `101S`). Bus
    /// stops have no such suffix, and nothing else in the feed states a direction.
    var mockDirection: String {
        switch id.last {
        case "N": "Northbound"
        case "S": "Southbound"
        case "E": "Eastbound"
        case "W": "Westbound"
        default: "All departures"
        }
    }

    /// The next few arrivals for a line here, ascending.
    ///
    /// Deterministic per platform and line, so the same stop always shows the same
    /// times — a stable hash rather than `String.hashValue`, which is seeded per
    /// process and would reshuffle on every launch.
    func mockDepartures(for line: Line, count: Int = 3) -> [MockDeparture] {
        let seed = Self.stableHash(id + line.id)
        var minutes = seed % 4
        return (0..<count).map { index in
            defer { minutes += 3 + (seed / (index + 2)) % 7 }
            return MockDeparture(id: "\(line.id)-\(index)", minutesAway: minutes)
        }
    }

    private static func stableHash(_ string: String) -> Int {
        var hash = 5_381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }
}

extension Line {

    /// The published colour, which MTA supplies for every route.
    var color: Color {
        var value: UInt64 = 0
        guard Scanner(string: colorHex).scanHexInt64(&value) else { return .gray }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
