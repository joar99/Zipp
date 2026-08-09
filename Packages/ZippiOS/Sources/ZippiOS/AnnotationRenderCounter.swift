import Foundation

/// Counts how many annotation bodies SwiftUI actually builds.
///
/// MEASUREMENT ONLY — temporary scaffolding to decide whether caching rendered
/// icons is worth it. Delete once that question is answered.
///
/// The number matters because it tells us what caching could possibly save: if
/// SwiftUI builds each annotation once per visible set, caching saves that once.
/// If it rebuilds them repeatedly, the saving is proportionally larger.
@MainActor
enum AnnotationRenderCounter {

    private static var dotCount = 0
    private static var labelCount = 0

    static func record(_ detail: MapViewModel.AnnotationDetail) {
        switch detail {
        case .dot: dotCount += 1
        case .label: labelCount += 1
        case .hidden: break
        }
    }

    /// Returns the counts since the last drain and resets them.
    static func drain() -> (dots: Int, labels: Int) {
        defer {
            dotCount = 0
            labelCount = 0
        }
        return (dotCount, labelCount)
    }
}
