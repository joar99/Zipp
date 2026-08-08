import Combine
import ZippFoundation
import ZippNavigation

@MainActor
final class AppCoordinator: ObservableObject, CoordinatorProtocol {

    var childCoordinators: [CoordinatorProtocol] = []

    let travelNavigationController = NavigationController()
    private let travelCoordinator: TravelCoordinator

    init() {
        Self.setupDependencies()
        travelCoordinator = TravelCoordinator(navigationController: travelNavigationController)
        append(child: travelCoordinator)
    }
}

private extension AppCoordinator {
    static func setupDependencies() {
        // MARK: - User Location Repository
        let userLocationRepository: UserLocationRepositoryProtocol = UserLocationRepository()
        DependencyContainer.shared.register(userLocationRepository, for: UserLocationRepositoryProtocol.self)
    }
}
