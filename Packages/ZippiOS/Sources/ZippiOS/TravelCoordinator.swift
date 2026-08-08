import ZippNavigation

@MainActor
final class TravelCoordinator: CoordinatorProtocol {

    var childCoordinators: [CoordinatorProtocol] = []

    private let navigationController: NavigationController
    private let travelViewModel: TravelViewModel

    init(navigationController: NavigationController) {
        self.navigationController = navigationController
        let travelViewModel = TravelViewModel()
        self.travelViewModel = travelViewModel
        travelViewModel.delegate = self
        let travelView = TravelView(viewModel: travelViewModel)
        navigationController.setRootView(travelView)
    }
}

extension TravelCoordinator: TravelViewModelDelegate {
}
