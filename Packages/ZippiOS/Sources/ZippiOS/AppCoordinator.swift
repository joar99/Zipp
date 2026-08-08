import Combine
import ZippData
import ZippFoundation
import ZippNavigation

@MainActor
final class AppCoordinator: ObservableObject, CoordinatorProtocol {

    var childCoordinators: [CoordinatorProtocol] = []

    let travelNavigationController = NavigationController()
    private let travelCoordinator: TravelCoordinator
    private let stopPlaceRepository: StopPlaceRepositoryProtocol

    init() {
        // Registration has to happen before anything resolves, which rules out
        // taking this as a defaulted initialiser parameter: default arguments are
        // evaluated at the call site, before this body runs.
        Self.setupDependencies()
        self.stopPlaceRepository = DependencyContainer.shared.resolveRequired()
        travelCoordinator = TravelCoordinator(navigationController: travelNavigationController)
        append(child: travelCoordinator)
        refreshStopPlaces()
    }
}

private extension AppCoordinator {

    /// Stops are served from local storage, so this only tops up a cache that is
    /// already good enough to render with.
    func refreshStopPlaces() {
        Task { [stopPlaceRepository] in
            await stopPlaceRepository.refresh()
        }
    }
}

private extension AppCoordinator {
    static func setupDependencies() {
        // MARK: - User Location Repository
        let userLocationRepository: UserLocationRepositoryProtocol = UserLocationRepository()
        DependencyContainer.shared.register(userLocationRepository, for: UserLocationRepositoryProtocol.self)

        // MARK: - Stop Place Repository
        // An unusable store leaves the app with nothing to show, so failing here
        // is preferable to limping on with every lookup silently empty.
        guard let modelContainer = try? ZippModelContainer.make() else {
            fatalError("Could not open the Zipp SwiftData store")
        }
        let stopPlaceRepository: StopPlaceRepositoryProtocol = StopPlaceRepository(
            modelContainer: modelContainer
        )
        DependencyContainer.shared.register(stopPlaceRepository, for: StopPlaceRepositoryProtocol.self)
    }
}
