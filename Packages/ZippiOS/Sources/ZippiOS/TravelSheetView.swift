import SwiftUI

struct TravelSheetView: View {

    @ObservedObject var viewModel: TravelSheetViewModel

    var body: some View {
        EmptyView()
    }
}

#Preview {
    TravelSheetView(viewModel: TravelSheetViewModel())
}
