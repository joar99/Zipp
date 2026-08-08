import SwiftUI

public struct NavigableView: Hashable, Identifiable {
    public let id = UUID()
    public let view: AnyView
    public let isRoot: Bool

    public init(view: AnyView, isRoot: Bool = false) {
        self.view = view
        self.isRoot = isRoot
    }

    public static func == (lhs: NavigableView, rhs: NavigableView) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
