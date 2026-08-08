import CoreLocation

@MainActor
public protocol UserLocationRepositoryProtocol {
    var locationUpdates: AsyncStream<CLLocationCoordinate2D> { get }
    func requestAuthorization()
}

@MainActor
public final class UserLocationRepository: NSObject, UserLocationRepositoryProtocol {

    public let locationUpdates: AsyncStream<CLLocationCoordinate2D>
    private let continuation: AsyncStream<CLLocationCoordinate2D>.Continuation
    private let locationManager = CLLocationManager()

    public override init() {
        var continuation: AsyncStream<CLLocationCoordinate2D>.Continuation!
        locationUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
        super.init()
        locationManager.delegate = self
    }

    public func requestAuthorization() {
        #if DEBUG
        continuation.yield(Self.debugLocation)
        #else
        locationManager.requestWhenInUseAuthorization()
        #endif
    }
}

#if DEBUG
private extension UserLocationRepository {
    // Apple Store, Fifth Avenue — Manhattan, near Central Park.
    static let debugLocation = CLLocationCoordinate2D(latitude: 40.7636, longitude: -73.9733)
}
#endif

extension UserLocationRepository: CLLocationManagerDelegate {

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        continuation.yield(coordinate)
    }
}
