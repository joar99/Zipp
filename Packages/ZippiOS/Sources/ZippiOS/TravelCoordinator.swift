import SwiftUI
import ZippFoundation
import ZippNavigation

@MainActor
final class TravelCoordinator: CoordinatorProtocol {

    private static let collapsedDetent = PresentationDetent.height(110)
    /// Roughly how much of the screen `.medium` takes. SwiftUI does not report a
    /// detent's height, so this is the sheet's own contract with the map.
    private static let mediumDetentCoverage = 0.5

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

    /// Selecting a stop is three things at once — highlight it, fly to it, and put
    /// its detail in the sheet. None of the three belongs to either view model
    /// alone, which is precisely why the coordinator owns the sequence.
    func mapViewModel(_ viewModel: MapViewModel, didSelect stopPlace: StopPlace) {
        // The map is told how much of itself is about to be covered, because the
        // coordinator is what decides the detent — left to guess, the map would
        // centre the stop underneath the sheet.
        viewModel.select(stopPlace, avoidingBottomFraction: Self.mediumDetentCoverage)
        travelSheetViewModel.show(stopPlace)
        navigationController.presentedModalDetent = .medium
    }
}

extension TravelCoordinator: TravelSheetViewModelDelegate {

    func travelSheetViewModelDidRequestClose(_ viewModel: TravelSheetViewModel) {
        viewModel.clear()
        mapViewModel.deselect()
        navigationController.presentedModalDetent = Self.collapsedDetent
    }
}
