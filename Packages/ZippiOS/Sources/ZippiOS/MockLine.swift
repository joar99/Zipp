import SwiftUI
import ZippFoundation

/// MOCK DATA — placeholder until the real `stop_times → trips → routes` join
/// exists. Delete this file wholesale when it does; nothing here should survive.
///
/// Real lines will come from `routes.txt`, which already carries official names and
/// colours, joined to platforms via `stop_times`. That join is 416 MB and is
/// deliberately deferred, so the shape of the UI is being built against invented
/// data first. Departures are a separate problem again — they are live data, and
/// MTA has no per-stop endpoint for subway.
struct MockLine: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: UInt32

    var color: Color {
        Color(
            red: Double((colorHex >> 16) & 0xFF) / 255,
            green: Double((colorHex >> 8) & 0xFF) / 255,
            blue: Double(colorHex & 0xFF) / 255
        )
    }
}

/// Minutes until a vehicle arrives.
struct MockDeparture: Identifiable, Hashable {
    let id: String
    let minutesAway: Int

    var label: String {
        minutesAway == 0 ? "Now" : "\(minutesAway) min"
    }
}

extension Platform {

    /// Deterministic per platform, so the same stop always shows the same lines and
    /// nothing flickers between redraws.
    var mockLines: [MockLine] {
        let seed = MockSeed.value(for: id)
        let count = 2 + seed % 3
        return (0..<count)
            .map { offset in
                MockLine.catalogue[(seed / (offset + 1) + offset * 5) % MockLine.catalogue.count]
            }
            // The seeding can repeat an entry; riders should not see one line twice.
            .reduce(into: [MockLine]()) { unique, line in
                if !unique.contains(line) { unique.append(line) }
            }
    }

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

    /// The next few arrivals for a line at this platform, ascending.
    func mockDepartures(for line: MockLine, count: Int = 3) -> [MockDeparture] {
        let seed = MockSeed.value(for: id + line.id)
        var minutes = seed % 4
        return (0..<count).map { index in
            defer { minutes += 3 + (seed / (index + 2)) % 7 }
            return MockDeparture(id: "\(line.id)-\(index)", minutesAway: minutes)
        }
    }
}

private extension MockLine {

    static let catalogue: [MockLine] = [
        MockLine(id: "1", name: "1", colorHex: 0xEE352E),
        MockLine(id: "2", name: "2", colorHex: 0xEE352E),
        MockLine(id: "3", name: "3", colorHex: 0xEE352E),
        MockLine(id: "A", name: "A", colorHex: 0x0039A6),
        MockLine(id: "C", name: "C", colorHex: 0x0039A6),
        MockLine(id: "E", name: "E", colorHex: 0x0039A6),
        MockLine(id: "N", name: "N", colorHex: 0xFCCC0A),
        MockLine(id: "Q", name: "Q", colorHex: 0xFCCC0A),
        MockLine(id: "7", name: "7", colorHex: 0xB933AD),
        MockLine(id: "L", name: "L", colorHex: 0xA7A9AC),
        MockLine(id: "M15", name: "M15", colorHex: 0x4D5357),
        MockLine(id: "B41", name: "B41", colorHex: 0x4D5357),
    ]
}

/// A stable hash. `String.hashValue` is seeded per process, so it would hand a
/// stop different mock lines on every launch — fine for correctness, confusing when
/// you are trying to judge a design.
private enum MockSeed {

    static func value(for string: String) -> Int {
        var hash = 5_381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }
}
