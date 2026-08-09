import MapKit
import SwiftUI
import ZippFoundation

struct MapView: View {

    @ObservedObject var viewModel: MapViewModel
    @State private var isDraggingMap = false

    var body: some View {
        GeometryReader { proxy in
            map(viewportSize: proxy.size)
        }
    }

    private func map(viewportSize: CGSize) -> some View {
        Map(position: $viewModel.cameraPosition) {
            ForEach(viewModel.visibleStopPlaces) { stopPlace in
                Annotation(coordinate: stopPlace.coordinate) {
                    StopPlaceAnnotation(stopPlace: stopPlace, detail: viewModel.annotationDetail)
                } label: {
                    Text(stopPlace.name)
                }
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.mapCameraDidChange(
                region: context.region,
                distance: context.camera.distance,
                // Needed to convert an annotation's size in points into degrees,
                // which is what stops labels being packed closer than they are wide.
                viewportSize: viewportSize
            )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDraggingMap else { return }
                    isDraggingMap = true
                    viewModel.userDidBeginDraggingMap()
                }
                .onEnded { _ in
                    isDraggingMap = false
                }
        )
    }
}
