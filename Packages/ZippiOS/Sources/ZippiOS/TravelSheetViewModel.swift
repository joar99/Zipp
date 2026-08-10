import Combine
import ZippFoundation

@MainActor
protocol TravelSheetViewModelDelegate: AnyObject {
    /// The rider dismissed the stop detail. Reporting rather than acting: clearing
    /// the map's selection and collapsing the sheet are the coordinator's calls.
    func travelSheetViewModelDidRequestClose(_ viewModel: TravelSheetViewModel)
}

@MainActor
final class TravelSheetViewModel: ObservableObject {

    /// The stop being described, or `nil` when the sheet is idle.
    @Published private(set) var stopPlace: StopPlace?

    weak var delegate: TravelSheetViewModelDelegate?

    func show(_ stopPlace: StopPlace) {
        self.stopPlace = stopPlace
    }

    func clear() {
        stopPlace = nil
    }

    func userDidTapClose() {
        delegate?.travelSheetViewModelDidRequestClose(self)
    }
}
