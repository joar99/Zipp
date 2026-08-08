import SwiftUI

public enum PresentedModal: Identifiable {
    case modal(AnyView)
    case fullScreen(AnyView)

    public var id: String { "modal" }
    public var view: AnyView {
        switch self {
        case .modal(let view): return view
        case .fullScreen(let view): return view
        }
    }

    public var isFullScreen: Bool {
        switch self {
        case .modal: return false
        case .fullScreen: return true
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
