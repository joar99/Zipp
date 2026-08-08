import SwiftUI

public struct SheetConfiguration {
    public var detents: Set<PresentationDetent>
    public var isDismissable: Bool
    public var backgroundInteractionEnabled: Bool

    public init(
        detents: Set<PresentationDetent> = [.large],
        isDismissable: Bool = true,
        backgroundInteractionEnabled: Bool = false
    ) {
        self.detents = detents
        self.isDismissable = isDismissable
        self.backgroundInteractionEnabled = backgroundInteractionEnabled
    }
}

public enum PresentedModal: Identifiable {
    case sheet(AnyView, SheetConfiguration)
    case fullScreen(AnyView)

    public var id: String { "modal" }

    public var view: AnyView {
        switch self {
        case .sheet(let view, _): return view
        case .fullScreen(let view): return view
        }
    }

    public var isFullScreen: Bool {
        switch self {
        case .sheet: return false
        case .fullScreen: return true
        }
    }

    public var sheetConfiguration: SheetConfiguration? {
        switch self {
        case .sheet(_, let configuration): return configuration
        case .fullScreen: return nil
        }
    }
}

public enum PresentedAlert: Identifiable {
    case message(title: String, message: String, dismiss: () -> Void)

    public var id: String { UUID().uuidString }

    @MainActor
    public var alert: Alert {
        switch self {
        case let .message(title, message, dismiss):
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(Text("OK"), action: dismiss)
            )
        }
    }
}
