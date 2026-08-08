import SwiftUI
import ZippFoundation

/// How a single stop draws itself on the map.
///
/// Everything here is deliberately cheap. Hundreds of these are on screen at
/// once and they are re-composited on every frame of a pan, so anything that
/// forces an offscreen pass — a material, a shadow, a blur — costs that price
/// hundreds of times per frame. Flat fills and strokes only.
struct StopPlaceAnnotation: View {

    let stopPlace: StopPlace
    let detail: MapViewModel.AnnotationDetail

    private var modes: [TransportMode] { stopPlace.modes.sortedForDisplay }
    private var tint: Color { stopPlace.modes.primary.tint }

    var body: some View {
        switch detail {
        case .hidden:
            EmptyView()
        case .dot:
            dot
        case .label:
            plate
        }
    }

    /// A duo-toned dot: the mode's colour, ringed so it stays legible against
    /// both parks and water.
    private var dot: some View {
        Circle()
            .fill(tint)
            .frame(width: 11, height: 11)
            .overlay {
                Circle().strokeBorder(.background, lineWidth: 2.5)
            }
    }

    private var plate: some View {
        HStack(spacing: 4) {
            ForEach(modes, id: \.self) { mode in
                Image(systemName: mode.symbolName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(mode.tint, in: Circle())
            }

            Text(stopPlace.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        // A solid fill rather than `.regularMaterial`: a material re-blurs its
        // backdrop every frame the map moves, which at this many annotations is
        // the single most expensive thing on screen.
        .background(.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
        .fixedSize()
    }
}

#Preview {
    VStack(spacing: 24) {
        StopPlaceAnnotation(stopPlace: .preview, detail: .dot)
        StopPlaceAnnotation(stopPlace: .preview, detail: .label)
    }
    .padding()
}

private extension StopPlace {
    static let preview = StopPlace(
        stopID: "127",
        feedID: "subway",
        name: "Times Sq-42 St",
        latitude: 40.75529,
        longitude: -73.987495,
        kind: .station,
        parentStationID: nil
    )
}
