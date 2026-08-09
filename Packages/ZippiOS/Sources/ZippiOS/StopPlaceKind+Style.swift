import SwiftUI
import ZippFoundation

/// Presentation for each mode.
///
/// Exhaustive by design: adding an operator to ``StopPlace/Kind`` will fail to
/// compile here until it is given a colour and a symbol.
extension StopPlace.Kind {

    var tint: Color {
        switch self {
        case .subway: Color(red: 0.00, green: 0.45, blue: 0.90)
        case .bus: Color(red: 0.36, green: 0.24, blue: 0.72)
        case .ferry: Color(red: 0.00, green: 0.60, blue: 0.68)
        case .path: Color(red: 0.78, green: 0.25, blue: 0.45)
        }
    }

    var symbolName: String {
        switch self {
        case .subway: "tram.fill.tunnel"
        case .bus: "bus.fill"
        case .ferry: "ferry.fill"
        case .path: "train.side.front.car"
        }
    }
}
