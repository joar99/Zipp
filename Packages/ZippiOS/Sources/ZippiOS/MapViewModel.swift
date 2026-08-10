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
    /// The rider tapped a stop. Reporting rather than acting: what selection means
    /// for the sheet and the camera is the coordinator's call, not the map's.
    func mapViewModel(_ viewModel: MapViewModel, didSelect stopPlace: StopPlace)
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
    /// Degrees clockwise from north, as reported by the compass.
    @Published private(set) var userHeading: CLLocationDirection?
    /// Which way the *map* is facing, which is not always north — the rider can
    /// rotate it.
    @Published private(set) var mapHeading: CLLocationDirection = 0
    @Published private(set) var visibleStopPlaces: [StopPlace] = []
    @Published private(set) var annotationDetail: AnnotationDetail = .hidden
    @Published private(set) var selectedStopPlaceID: String?
    @Published var cameraPosition = MapCameraPosition.automatic

    weak var delegate: MapViewModelDelegate?

    /// How much map height a metre of camera distance buys, measured from the map
    /// itself rather than assumed.
    ///
    /// It is nowhere near 1: a camera 1,400 m away shows about 620 m of ground. The
    /// exact figure depends on the viewport's aspect ratio and field of view, so it
    /// differs by device and orientation — hence measuring it rather than baking in
    /// a constant that would be wrong on an iPad. Seeded with the iPhone value so
    /// the very first selection is already close.
    private var visibleHeightPerCameraMetre = 0.445

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
        Task {
            for await heading in userLocationRepository.headingUpdates {
                userHeading = heading
            }
        }
    }

    /// How far to rotate the heading cone on screen.
    ///
    /// The compass reports degrees from north, but annotations stay screen-aligned
    /// while the map underneath can be rotated, so the map's own heading has to be
    /// subtracted or the cone points somewhere the rider is not facing.
    var userHeadingRotation: Angle? {
        guard let userHeading else { return nil }
        return .degrees(userHeading - mapHeading)
    }

    func userDidBeginDraggingMap() {
        delegate?.mapViewModelDidBeginDragging(self)
    }

    func userDidTapStopPlace(_ stopPlace: StopPlace) {
        delegate?.mapViewModel(self, didSelect: stopPlace)
    }

    /// Marks a stop as selected and flies the camera to it.
    ///
    /// The distance lands inside the `.label` threshold, so a selected stop is
    /// always shown named rather than as an anonymous dot.
    ///
    /// - Parameter avoidingBottomFraction: how much of the map the sheet covers.
    ///   Centring on the stop would put it underneath the sheet, so the camera
    ///   centre is shifted *away* from the viewer's up-direction, which raises the
    ///   stop into the part of the map that is actually visible.
    ///
    ///   UIKit would do this with `setVisibleMapRect(_:edgePadding:animated:)`.
    ///   SwiftUI's `Map` exposes no inset or padding of any kind — verified against
    ///   the SDK — so the offset is computed by hand.
    func select(_ stopPlace: StopPlace, avoidingBottomFraction: Double = 0) {
        selectedStopPlaceID = stopPlace.id

        // Half of the covered fraction, because the shift moves the stop from the
        // centre of the whole map to the centre of the part still showing.
        let visibleHeight = Self.selectionCameraDistance * visibleHeightPerCameraMetre
        let shift = visibleHeight * avoidingBottomFraction / 2

        // Shift along the heading reversed, i.e. "down the screen", whatever way the
        // map happens to be rotated. A plain latitude offset would be wrong the
        // moment the rider turns the map.
        let centre = Self.coordinate(
            stopPlace.coordinate,
            movedBy: shift,
            bearing: mapHeading + 180
        )


        withAnimation(.easeInOut(duration: 0.45)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: centre,
                    distance: Self.selectionCameraDistance,
                    heading: mapHeading
                )
            )
        }
    }

    func deselect() {
        selectedStopPlaceID = nil
    }

    func mapCameraDidChange(
        region: MKCoordinateRegion,
        distance: CLLocationDistance,
        heading: CLLocationDirection,
        viewportSize: CGSize
    ) {
        if mapHeading != heading { mapHeading = heading }

        // Recalibrate from what the map is actually showing. Ignored at world scale,
        // where the Mercator projection stretches a degree of latitude far enough to
        // make the ratio meaningless.
        if region.span.latitudeDelta < 1, distance > 0 {
            visibleHeightPerCameraMetre = (region.span.latitudeDelta * 111_320) / distance
        }

        let detail = Self.annotationDetail(forCameraDistance: distance)

        guard detail != .hidden else {
            visibleStopsTask?.cancel()
            annotationDetail = detail
            if !visibleStopPlaces.isEmpty { visibleStopPlaces = [] }
            return
        }

        loadVisibleStopPlaces(in: region, detail: detail, viewportSize: viewportSize)
    }
}

// MARK: - Loading

private extension MapViewModel {

    /// Long enough that a flick through the city issues one query rather than
    /// one per frame, short enough to feel immediate when the map settles.
    static let cameraSettleDelay = Duration.milliseconds(150)


    func loadVisibleStopPlaces(
        in region: MKCoordinateRegion,
        detail: AnnotationDetail,
        viewportSize: CGSize
    ) {
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

            var decimated = Self.decimated(
                stopPlaces,
                in: region,
                limit: Self.renderBudget(for: detail),
                minimumSpacing: Self.footprint(for: detail),
                viewportSize: viewportSize
            )

            // Decimation is blind to selection, so a selected stop can lose its
            // grid cell to a higher-ranked neighbour and silently vanish from the
            // map while the sheet still describes it. Put it back.
            if let selectedStopPlaceID,
               !decimated.contains(where: { $0.id == selectedStopPlaceID }),
               let selected = stopPlaces.first(where: { $0.id == selectedStopPlaceID }) {
                decimated.append(selected)
            }

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

    /// Close enough to land in `.label` detail, so a selected stop is never a dot.
    static let selectionCameraDistance: CLLocationDistance = 1_400

    /// Moves a coordinate `distance` metres along `bearing`.
    ///
    /// A flat-earth approximation, which is accurate far beyond the few hundred
    /// metres this is ever asked for.
    static func coordinate(
        _ coordinate: CLLocationCoordinate2D,
        movedBy distance: CLLocationDistance,
        bearing: CLLocationDirection
    ) -> CLLocationCoordinate2D {
        let metresPerDegree = 111_320.0
        let radians = bearing * .pi / 180
        let latitude = coordinate.latitude + (distance * cos(radians)) / metresPerDegree
        let longitude = coordinate.longitude
            + (distance * sin(radians)) / (metresPerDegree * cos(coordinate.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

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

    /// Roughly how much room one annotation needs, in points, including breathing
    /// space. The plate is generous on width because it sizes itself to the stop's
    /// name, and a long name like "Van Cortlandt Park-242 St" is far wider than a
    /// short one.
    static func footprint(for detail: AnnotationDetail) -> CGSize {
        switch detail {
        case .hidden: .zero
        case .dot: CGSize(width: 26, height: 26)
        case .label: CGSize(width: 190, height: 40)
        }
    }

    /// Thins a dense set of stops down to something drawable, keeping at most one
    /// per grid cell.
    ///
    /// Cell size is the larger of two constraints:
    ///
    /// 1. **the render budget** — enough cells to fill it, and no more;
    /// 2. **the annotation's own size** — a cell narrower than the thing drawn in
    ///    it guarantees neighbours overlap, which is what a purely budget-derived
    ///    grid did: 60 plates over a phone screen makes ~80pt cells for annotations
    ///    that are twice that wide.
    ///
    /// The grid is anchored to absolute coordinates rather than to the visible
    /// region, so panning does not reshuffle which stop wins a cell. Together with
    /// a deterministic tie-break, that is what stops annotations flickering in and
    /// out as the map moves.
    static func decimated(
        _ stopPlaces: [StopPlace],
        in region: MKCoordinateRegion,
        limit: Int,
        minimumSpacing: CGSize,
        viewportSize: CGSize
    ) -> [StopPlace] {
        guard !stopPlaces.isEmpty else { return [] }

        let aspectRatio = max(region.span.longitudeDelta / max(region.span.latitudeDelta, .leastNonzeroMagnitude), 0.1)
        let columns = max(1, Int((Double(limit) * aspectRatio).squareRoot().rounded()))
        let rows = max(1, limit / columns)

        var cellWidth = region.span.longitudeDelta / Double(columns)
        var cellHeight = region.span.latitudeDelta / Double(rows)

        // Convert the annotation's footprint from points into degrees and use it
        // as a floor, so cells are never smaller than what they hold.
        if viewportSize.width > 0, viewportSize.height > 0 {
            cellWidth = max(cellWidth, region.span.longitudeDelta * (minimumSpacing.width / viewportSize.width))
            cellHeight = max(cellHeight, region.span.latitudeDelta * (minimumSpacing.height / viewportSize.height))
        }
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
        case .subway, .rail: 2
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
