import Combine
import CoreLocation
import MapKit
import SwiftUI
import ZippFoundation

@MainActor
protocol MapViewModelDelegate: AnyObject {
    func mapViewModelDidBeginDragging(_ viewModel: MapViewModel)
}

@MainActor
final class MapViewModel: ObservableObject {

    @Published private(set) var userLocation: CLLocationCoordinate2D?
    @Published var cameraPosition = MapCameraPosition.automatic

    weak var delegate: MapViewModelDelegate?

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
        delegate?.mapViewModelDidBeginDragging(self)
    }
}
