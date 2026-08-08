import Combine
import CoreLocation
import MapKit
import SwiftUI
import ZippFoundation

@MainActor
protocol TravelViewModelDelegate: AnyObject {
}

@MainActor
final class TravelViewModel: ObservableObject {

    static let collapsedDetent = PresentationDetent.height(110)

    @Published private(set) var userLocation: CLLocationCoordinate2D?
    @Published var cameraPosition = MapCameraPosition.automatic
    @Published var sheetDetent = TravelViewModel.collapsedDetent

    weak var delegate: TravelViewModelDelegate?

    private let userLocationRepository: UserLocationRepositoryProtocol

    init(userLocationRepository: UserLocationRepositoryProtocol = DependencyContainer.shared.resolveRequired()) {
        self.userLocationRepository = userLocationRepository
        userLocationRepository.requestAuthorization()
        Task {
            for await coordinate in userLocationRepository.locationUpdates {
                let isInitialLocation = userLocation == nil
                userLocation = coordinate
                if isInitialLocation {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                        )
                    )
                }
            }
        }
    }

    func userDidBeginDraggingMap() {
        sheetDetent = Self.collapsedDetent
    }
}
