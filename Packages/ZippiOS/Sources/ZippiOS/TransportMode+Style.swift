import SwiftUI
import ZippFoundation

extension TransportMode {

    var tint: Color {
        switch self {
        case .subway: Color(red: 0.00, green: 0.45, blue: 0.90)
        case .bus: Color(red: 0.36, green: 0.24, blue: 0.72)
        case .ferry: Color(red: 0.00, green: 0.60, blue: 0.68)
        case .rail: Color(red: 0.78, green: 0.25, blue: 0.45)
        case .tram: Color(red: 0.16, green: 0.58, blue: 0.30)
        case .other: Color.secondary
        }
    }

    var symbolName: String {
        switch self {
        case .subway: "tram.fill.tunnel"
        case .bus: "bus.fill"
        case .ferry: "ferry.fill"
        case .rail: "train.side.front.car"
        case .tram: "tram.fill"
        case .other: "mappin"
        }
    }
}

extension Collection<TransportMode> {

    /// A stable order, so a stop's icons never reshuffle between redraws.
    var sortedForDisplay: [TransportMode] {
        sorted { $0.rawValue < $1.rawValue }
    }

    var primary: TransportMode {
        sortedForDisplay.first ?? .other
    }
}
