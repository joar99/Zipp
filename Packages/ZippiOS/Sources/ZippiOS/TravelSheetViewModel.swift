import Combine

@MainActor
protocol TravelSheetViewModelDelegate: AnyObject {
}

@MainActor
final class TravelSheetViewModel: ObservableObject {

    weak var delegate: TravelSheetViewModelDelegate?
}
