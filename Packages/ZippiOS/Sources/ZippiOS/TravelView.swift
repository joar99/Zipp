import MapKit
import SwiftUI
import ZippFoundation

struct TravelView: View {

    @ObservedObject var viewModel: TravelViewModel
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
            .sheet(isPresented: .constant(true)) {
                EmptyView()
                    .presentationDetents(
                        [TravelViewModel.collapsedDetent, .medium, .large],
                        selection: $viewModel.sheetDetent
                    )
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
    }
}

#Preview {
    TravelView(viewModel: TravelViewModel(userLocationRepository: UserLocationRepository()))
}
