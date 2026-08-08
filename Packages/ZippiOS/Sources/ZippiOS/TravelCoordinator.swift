import SwiftUI
import ZippNavigation

@MainActor
final class TravelCoordinator: CoordinatorProtocol {

    private static let collapsedDetent = PresentationDetent.height(110)

    var childCoordinators: [CoordinatorProtocol] = []

    private let navigationController: NavigationController
    private let mapViewModel: MapViewModel
    private let travelSheetViewModel: TravelSheetViewModel

    init(navigationController: NavigationController) {
        self.navigationController = navigationController

        let mapViewModel = MapViewModel()
        let travelSheetViewModel = TravelSheetViewModel()
        self.mapViewModel = mapViewModel
        self.travelSheetViewModel = travelSheetViewModel
        mapViewModel.delegate = self
        travelSheetViewModel.delegate = self

        navigationController.setRootView(MapView(viewModel: mapViewModel))
        navigationController.presentModal(
            TravelSheetView(viewModel: travelSheetViewModel),
            configuration: SheetConfiguration(
                detents: [Self.collapsedDetent, .medium, .large],
                isDismissable: false,
                backgroundInteractionEnabled: true
            )
        )
    }
}

extension TravelCoordinator: MapViewModelDelegate {
    func mapViewModelDidBeginDragging(_ viewModel: MapViewModel) {
        navigationController.presentedModalDetent = Self.collapsedDetent
    }
}

extension TravelCoordinator: TravelSheetViewModelDelegate {
    
}
