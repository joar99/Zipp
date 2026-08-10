import SwiftUI
import ZippFoundation

struct TravelSheetView: View {

    @ObservedObject var viewModel: TravelSheetViewModel

    var body: some View {
        ZStack {
            if let stopPlace = viewModel.stopPlace {
                StopPlaceDetail(stopPlace: stopPlace, onClose: viewModel.userDidTapClose)
                    // Slides up from below rather than fading, so it reads as
                    // content arriving in the sheet instead of appearing on top
                    // of it.
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: viewModel.stopPlace?.id)
    }
}

/// The stop's platforms, and the lines that call at each.
private struct StopPlaceDetail: View {

    let stopPlace: StopPlace
    let onClose: () -> Void

    private var platforms: [Platform] { stopPlace.kind.platforms }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(platforms) { platform in
                        PlatformSection(platform: platform)
                    }
                }
            }
            // The rows are not interactive yet, but the sheet is draggable, so the
            // scroll view must be able to take the gesture at the medium detent.
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stopPlace.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)

                Text(platformSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        // Clears the sheet's drag indicator, which sits in the top ~20pt.
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var platformSummary: String {
        switch stopPlace.kind {
        case .bus: "Bus stop"
        case .ferry: "Ferry landing"
        case .subway, .path:
            platforms.count == 1 ? "1 platform" : "\(platforms.count) platforms"
        }
    }
}

/// One direction, and every line that leaves from it.
private struct PlatformSection: View {

    let platform: Platform

    private var lines: [MockLine] { platform.mockLines }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(platform.mockDirection)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(lines) { line in
                LineDeparturesRow(
                    line: line,
                    departures: platform.mockDepartures(for: line)
                )
                if line.id != lines.last?.id {
                    Divider().padding(.leading, 76)
                }
            }
        }
    }
}

/// One line and when it next leaves.
///
/// Sized as a full-width row rather than a compact badge: these become tappable
/// (a line is the obvious way into its route), and a target should be built at the
/// size it will need rather than grown into later.
private struct LineDeparturesRow: View {

    let line: MockLine
    let departures: [MockDeparture]

    var body: some View {
        HStack(spacing: 14) {
            Text(line.name)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 44, height: 44)
                .background(line.color, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                // The soonest departure carries the emphasis; the rest are context.
                Text(departures.first?.label ?? "No service")
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()

                if departures.count > 1 {
                    Text("then " + departures.dropFirst().map(\.label).joined(separator: " · "))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // A comfortable target, and the whole row is the target rather than just
        // the badge or the text inside it.
        .frame(minHeight: 68)
        .contentShape(.rect)
    }
}

#Preview {
    let viewModel = TravelSheetViewModel()
    viewModel.show(
        StopPlace(
            id: "subway:127",
            name: "Times Sq-42 St",
            latitude: 40.75529,
            longitude: -73.987495,
            kind: .subway([Platform(id: "127N"), Platform(id: "127S")])
        )
    )
    return TravelSheetView(viewModel: viewModel)
}
