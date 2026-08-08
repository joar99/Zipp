import MapKit
import SwiftUI
import ZippFoundation

struct MapView: View {

    @ObservedObject var viewModel: MapViewModel
    @State private var isDraggingMap = false

    var body: some View {
        Map(position: $viewModel.cameraPosition)
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
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

#Preview {
    MapView(viewModel: MapViewModel(userLocationRepository: UserLocationRepository()))
}
