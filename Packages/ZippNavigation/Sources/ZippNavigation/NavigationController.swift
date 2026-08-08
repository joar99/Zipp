import SwiftUI
import Combine

public struct NavigationControllerPresenter: View {

    @ObservedObject var navigationController: NavigationController

    public init(navigationController: NavigationController) {
        self.navigationController = navigationController
    }

    public var body: some View {
        NavigationStack(path: $navigationController.navigationPath) {
            EmptyView()
                .navigationDestination(for: NavigableView.self) { navigableView in
                    navigableView.view
                        .applyAlert(presentedAlert: $navigationController.presentedAlert)
                        .applyModal(
                            presentedModal: $navigationController.presentedModal,
                            presentedModalDetent: $navigationController.presentedModalDetent
                        )
                        .navigationBarBackButtonHidden(navigableView.isRoot)
                        .disablesInteractivePopGesture(navigableView.isRoot)
                }
        }
        .onChange(of: navigationController.navigationPath) {
            navigationController.syncPoppedWrappers()
        }
    }
}

@MainActor
public final class NavigationController: ObservableObject {

    @Published public var navigationPath = NavigationPath()
    @Published public var presentedModal: PresentedModal?
    @Published public var presentedModalDetent: PresentationDetent = .medium
    @Published public var presentedAlert: PresentedAlert?

    private var wrappers: [NavigableView] = []

    public init() {}

    public func pushView<V: View>(_ view: V) {
        let navigableView = NavigableView(view: AnyView(view))
        wrappers.append(navigableView)
        navigationPath.append(navigableView)
    }

    public func setRootView<V: View>(_ view: V) {
        let navigableView = NavigableView(view: AnyView(view), isRoot: true)
        wrappers = [navigableView]
        navigationPath = NavigationPath()
        navigationPath.append(navigableView)
    }

    public func pop() {
        guard wrappers.count > 1 else { return }
        wrappers.removeLast()
        navigationPath.removeLast()
    }

    public func popToRoot() {
        guard let root = wrappers.first else { return }
        wrappers = [root]
        navigationPath = NavigationPath()
        navigationPath.append(root)
    }

    public func presentModal<V: View>(_ view: V, configuration: SheetConfiguration = SheetConfiguration()) {
        presentedModalDetent = configuration.detents.first ?? .medium
        presentedModal = .sheet(AnyView(view), configuration)
    }

    public func presentFullScreenModal<V: View>(_ view: V) {
        presentedModal = .fullScreen(AnyView(view))
    }

    public func dismissModal() {
        presentedModal = nil
    }

    public func presentAlert(_ alert: PresentedAlert) {
        presentedAlert = alert
    }

    public func dismissAlert() {
        presentedAlert = nil
    }

    fileprivate func syncPoppedWrappers() {
        while wrappers.count > navigationPath.count {
            wrappers.removeLast()
        }
    }
}
