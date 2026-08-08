import MapKit
import SwiftUI
import ZippFoundation

struct MapView: View {

    @ObservedObject var viewModel: MapViewModel
    @State private var isDraggingMap = false

    var body: some View {
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
                distance: context.camera.distance
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
