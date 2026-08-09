import Combine
import CoreLocation
import MapKit
import OSLog
import SwiftUI
import ZippFoundation

private let logger = Logger(subsystem: "no.jonas.Zipp", category: "MapViewModel")

@MainActor
protocol MapViewModelDelegate: AnyObject {
    func mapViewModelDidBeginDragging(_ viewModel: MapViewModel)
}

@MainActor
final class MapViewModel: ObservableObject {

    /// How much of a stop to draw, chosen by how close the camera is.
    enum AnnotationDetail: Equatable {
        /// Too far out for individual stops to mean anything.
        case hidden
        /// A small coloured dot.
        case dot
        /// A rounded plate carrying the mode icons and the stop's name.
        case label
    }

    @Published private(set) var userLocation: CLLocationCoordinate2D?
    @Published private(set) var visibleStopPlaces: [StopPlace] = []
    @Published private(set) var annotationDetail: AnnotationDetail = .hidden
    @Published var cameraPosition = MapCameraPosition.automatic

    weak var delegate: MapViewModelDelegate?

    private let userLocationRepository: UserLocationRepositoryProtocol
    private let stopPlaceRepository: StopPlaceRepositoryProtocol
    private var visibleStopsTask: Task<Void, Never>?

    init(
        userLocationRepository: UserLocationRepositoryProtocol = DependencyContainer.shared.resolveRequired(),
        stopPlaceRepository: StopPlaceRepositoryProtocol = DependencyContainer.shared.resolveRequired()
    ) {
        self.userLocationRepository = userLocationRepository
        self.stopPlaceRepository = stopPlaceRepository
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

    func mapCameraDidChange(region: MKCoordinateRegion, distance: CLLocationDistance) {
        let detail = Self.annotationDetail(forCameraDistance: distance)
        logger.debug("camera \(Int(distance))m -> \(String(describing: detail), privacy: .public)")

        guard detail != .hidden else {
            visibleStopsTask?.cancel()
            annotationDetail = detail
            if !visibleStopPlaces.isEmpty { visibleStopPlaces = [] }
            return
        }

        loadVisibleStopPlaces(in: region, detail: detail)
    }
}

// MARK: - Loading

private extension MapViewModel {

    /// Long enough that a flick through the city issues one query rather than
    /// one per frame, short enough to feel immediate when the map settles.
    static let cameraSettleDelay = Duration.milliseconds(150)

    func loadVisibleStopPlaces(in region: MKCoordinateRegion, detail: AnnotationDetail) {
        visibleStopsTask?.cancel()
        visibleStopsTask = Task { [weak self, stopPlaceRepository] in
            try? await Task.sleep(for: Self.cameraSettleDelay)
            guard !Task.isCancelled else { return }

            let bounds = CoordinateBounds(region: region)
            let stopPlaces: [StopPlace]
            do {
                stopPlaces = try await stopPlaceRepository.stopPlaces(in: bounds)
            } catch {
                // Swallowing this silently once cost an afternoon: the map simply
                // drew nothing while the store was fine and the fetch was throwing.
                logger.error("Loading stop places failed, \(error, privacy: .public)")
                return
            }
            guard !Task.isCancelled, let self else { return }

            let decimated = Self.decimated(
                stopPlaces,
                in: region,
                limit: Self.renderBudget(for: detail)
            )
            logger.debug("\(stopPlaces.count) in bounds -> \(decimated.count) rendered")

            // Detail and contents move together. Applying the detail change
            // early would briefly render a dot-sized crowd as full plates, which
            // is exactly the workload the budgets exist to avoid.
            if self.annotationDetail != detail {
                self.annotationDetail = detail
            }
            // Re-assigning an identical list makes SwiftUI diff every annotation
            // for no visual change.
            guard decimated.map(\.id) != self.visibleStopPlaces.map(\.id) else { return }
            self.visibleStopPlaces = decimated
        }
    }
}

// MARK: - Zoom thresholds

private extension MapViewModel {

    static func annotationDetail(forCameraDistance distance: CLLocationDistance) -> AnnotationDetail {
        switch distance {
        case ..<3_000: .label
        case ..<12_000: .dot
        default: .hidden
        }
    }
}

// MARK: - Decimation

private extension MapViewModel {

    /// How many annotations each detail level is allowed to draw.
    ///
    /// A plate costs far more than a dot — it lays out text, sizes itself to that
    /// text, and covers a much larger area — so the two cannot share a budget.
    /// These are starting points, tuned by eye rather than measurement.
    static func renderBudget(for detail: AnnotationDetail) -> Int {
        switch detail {
        case .hidden: 0
        case .dot: 250
        case .label: 60
        }
    }

    /// Thins a dense set of stops down to something drawable, keeping at most one
    /// per grid cell.
    ///
    /// The grid is anchored to absolute coordinates rather than to the visible
    /// region, so panning does not reshuffle which stop wins a cell. Together
    /// with a deterministic tie-break that keeps the selection stable frame to
    /// frame, which is what stops annotations flickering in and out as the map
    /// moves.
    static func decimated(
        _ stopPlaces: [StopPlace],
        in region: MKCoordinateRegion,
        limit: Int
    ) -> [StopPlace] {
        guard stopPlaces.count > limit else { return stopPlaces }

        let aspectRatio = max(region.span.longitudeDelta / max(region.span.latitudeDelta, .leastNonzeroMagnitude), 0.1)
        let columns = max(1, Int((Double(limit) * aspectRatio).squareRoot().rounded()))
        let rows = max(1, limit / columns)

        let cellWidth = region.span.longitudeDelta / Double(columns)
        let cellHeight = region.span.latitudeDelta / Double(rows)
        guard cellWidth > 0, cellHeight > 0 else { return Array(stopPlaces.prefix(limit)) }

        struct Cell: Hashable {
            let row: Int
            let column: Int
        }

        var winners: [Cell: StopPlace] = [:]
        winners.reserveCapacity(limit)

        for stopPlace in stopPlaces {
            let cell = Cell(
                row: Int((stopPlace.latitude / cellHeight).rounded(.down)),
                column: Int((stopPlace.longitude / cellWidth).rounded(.down))
            )
            if let incumbent = winners[cell] {
                if outranks(stopPlace, incumbent) { winners[cell] = stopPlace }
            } else {
                winners[cell] = stopPlace
            }
        }

        return winners.values
            .sorted { outranks($0, $1) }
            .prefix(limit)
            .sorted { $0.id < $1.id }
    }

    /// Rail beats ferry beats bus, and ties break on identifier so the result never
    /// depends on the order the store happened to return rows in.
    ///
    /// A rail station is a better landmark than any one of the bus stops around
    /// it, and there are nine bus stops for every rail station, so without this the
    /// buses would crowd the stations out of their cells.
    static func outranks(_ lhs: StopPlace, _ rhs: StopPlace) -> Bool {
        let lhsRank = rank(lhs.kind)
        let rhsRank = rank(rhs.kind)
        if lhsRank != rhsRank { return lhsRank > rhsRank }
        return lhs.id < rhs.id
    }

    static func rank(_ kind: StopPlace.Kind) -> Int {
        switch kind {
        case .subway, .path: 2
        case .ferry: 1
        case .bus: 0
        }
    }
}

private extension CoordinateBounds {

    init(region: MKCoordinateRegion) {
        self.init(
            minimumLatitude: region.center.latitude - region.span.latitudeDelta / 2,
            maximumLatitude: region.center.latitude + region.span.latitudeDelta / 2,
            minimumLongitude: region.center.longitude - region.span.longitudeDelta / 2,
            maximumLongitude: region.center.longitude + region.span.longitudeDelta / 2
        )
    }
}
