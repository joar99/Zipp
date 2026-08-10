import CoreLocation

@MainActor
public protocol UserLocationRepositoryProtocol {
    var locationUpdates: AsyncStream<CLLocationCoordinate2D> { get }
    /// Degrees clockwise from north. Separate from location because the two
    /// arrive independently and at very different rates — heading changes as the
    /// rider turns on the spot, without moving at all.
    var headingUpdates: AsyncStream<CLLocationDirection> { get }
    func requestAuthorization()
}

@MainActor
public final class UserLocationRepository: NSObject, UserLocationRepositoryProtocol {

    public let locationUpdates: AsyncStream<CLLocationCoordinate2D>
    public let headingUpdates: AsyncStream<CLLocationDirection>

    private let locationContinuation: AsyncStream<CLLocationCoordinate2D>.Continuation
    private let headingContinuation: AsyncStream<CLLocationDirection>.Continuation
    private let locationManager = CLLocationManager()

    public override init() {
        var locationContinuation: AsyncStream<CLLocationCoordinate2D>.Continuation!
        locationUpdates = AsyncStream { locationContinuation = $0 }
        self.locationContinuation = locationContinuation

        var headingContinuation: AsyncStream<CLLocationDirection>.Continuation!
        headingUpdates = AsyncStream { headingContinuation = $0 }
        self.headingContinuation = headingContinuation

        super.init()
        locationManager.delegate = self
    }

    public func requestAuthorization() {
        #if DEBUG
        locationContinuation.yield(Self.debugLocation)
        headingContinuation.yield(Self.debugHeading)
        #else
        locationManager.requestWhenInUseAuthorization()
        #endif
    }
}

#if DEBUG
private extension UserLocationRepository {
    // Apple Store, Fifth Avenue — Manhattan, near Central Park.
    static let debugLocation = CLLocationCoordinate2D(latitude: 40.7636, longitude: -73.9733)
    // Northeast. Deliberately off-axis so a cone that is not rotating is obvious
    // rather than plausible — the simulator has no compass to fall back on.
    static let debugHeading: CLLocationDirection = 45
}
#endif

extension UserLocationRepository: CLLocationManagerDelegate {

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        default:
            break
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        locationContinuation.yield(coordinate)
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // `trueHeading` is negative until the device has a location fix to derive
        // magnetic declination from; magnetic north is the honest fallback.
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard heading >= 0 else { return }
        headingContinuation.yield(heading)
    }
}
