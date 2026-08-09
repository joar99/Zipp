import Foundation

public extension Duration {

    /// Milliseconds, to one decimal place, for logging.
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        let total = Double(seconds) * 1_000 + Double(attoseconds) / 1_000_000_000_000_000
        return (total * 10).rounded() / 10
    }
}
