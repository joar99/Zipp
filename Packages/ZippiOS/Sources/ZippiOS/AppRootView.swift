import SwiftUI
import ZippNavigation

public struct AppRootView: View {

    @StateObject private var appCoordinator = AppCoordinator()

    public init() {}

    public var body: some View {
        NavigationControllerPresenter(navigationController: appCoordinator.travelNavigationController)
    }
}

#Preview {
    AppRootView()
}
