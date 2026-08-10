import SwiftUI
import ZippFoundation

/// How a single stop draws itself on the map.
///
/// Everything here is deliberately cheap. Hundreds are on screen at once and they
/// are re-composited on every frame of a pan, so anything forcing an offscreen
/// pass — a material, a shadow, a blur — costs that price hundreds of times per
/// frame. Flat fills and strokes only.
struct StopPlaceAnnotation: View {

    let stopPlace: StopPlace
    let detail: MapViewModel.AnnotationDetail
    var isSelected = false

    private var tint: Color { stopPlace.kind.tint }

    var body: some View {
        Group {
            if isSelected {
                // Selection ignores the zoom detail. Selecting always flies the
                // camera close enough for a label anyway, and a selected stop
                // rendered as an anonymous dot would be a strange thing to show.
                selectedPlate
            } else {
                switch detail {
                case .hidden:
                    EmptyView()
                case .dot:
                    dot
                case .label:
                    plate
                }
            }
        }
        // Animate here, on the annotation, rather than wrapping the data change in
        // `withAnimation`. Measured: this stays at one body evaluation per
        // annotation, while animating the data keeps departing annotations alive
        // for the duration — and since `detail` is shared, a hundred outgoing dots
        // each draw themselves as full plates on the way out, six times the work.
        .animation(.snappy(duration: 0.22), value: detail)
        .animation(.snappy(duration: 0.28), value: isSelected)
    }

    /// A duo-toned dot: the mode's colour, ringed so it stays legible against both
    /// parks and water.
    private var dot: some View {
        Circle()
            .fill(tint)
            .frame(width: 11, height: 11)
            .overlay {
                Circle().strokeBorder(.background, lineWidth: 2.5)
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    private var plate: some View {
        HStack(spacing: 4) {
            Image(systemName: stopPlace.kind.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(tint, in: Circle())

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
        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }

    /// The selected form: inverted, so the chosen stop reads as the subject of the
    /// screen rather than one more option among the stops around it.
    private var selectedPlate: some View {
        HStack(spacing: 6) {
            Image(systemName: stopPlace.kind.symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(.white, in: Circle())

            Text(stopPlace.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .padding(.leading, 5)
        .padding(.trailing, 11)
        .padding(.vertical, 5)
        .background(tint, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
        .fixedSize()
        .transition(.scale(scale: 0.7).combined(with: .opacity))
    }
}

#Preview {
    VStack(spacing: 24) {
        StopPlaceAnnotation(stopPlace: .preview, detail: .dot)
        StopPlaceAnnotation(stopPlace: .preview, detail: .label)
        StopPlaceAnnotation(stopPlace: .preview, detail: .label, isSelected: true)
    }
    .padding()
}

private extension StopPlace {
    static let preview = StopPlace(
        id: "subway:127",
        name: "Times Sq-42 St",
        latitude: 40.75529,
        longitude: -73.987495,
        kind: .subway([Platform(id: "127N"), Platform(id: "127S")])
    )
}
