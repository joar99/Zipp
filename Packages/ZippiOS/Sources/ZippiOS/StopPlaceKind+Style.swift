import SwiftUI
import ZippFoundation

/// Presentation for each mode.
///
/// Exhaustive by design: adding an operator to ``StopPlace/Kind`` will fail to
/// compile here until it is given a colour and a symbol.
extension StopPlace.Kind {

    /// Chosen to sit far apart in hue — roughly blue, orange, cyan, magenta — so
    /// they stay separable at dot size against a muted map. The previous blue and
    /// purple were close enough to read as the same colour once shrunk to 11pt.
    var tint: Color {
        switch self {
        case .subway: Color(red: 0.00, green: 0.38, blue: 1.00)
        case .bus: Color(red: 1.00, green: 0.45, blue: 0.00)
        case .ferry: Color(red: 0.00, green: 0.72, blue: 0.72)
        case .rail: Color(red: 0.90, green: 0.10, blue: 0.55)
        }
    }

    var symbolName: String {
        switch self {
        case .subway: "tram.fill.tunnel"
        case .bus: "bus.fill"
        case .ferry: "ferry.fill"
        case .rail: "train.side.front.car"
        }
    }
}
