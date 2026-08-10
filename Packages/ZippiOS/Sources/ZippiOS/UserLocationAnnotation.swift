import SwiftUI

/// Where the rider is, and which way they are facing.
///
/// Deliberately not MapKit's built-in `UserAnnotation()`: that reads CoreLocation
/// directly, so it would ignore whatever ``UserLocationRepositoryProtocol`` is
/// publishing — including the fixed Manhattan coordinate it yields in debug
/// builds. Driving this from the repository keeps one source of truth for "where
/// the user is", and keeps the map honest in testing.
///
/// Only ever one of these on screen, so unlike ``StopPlaceAnnotation`` it can
/// afford a shadow and a running animation.
struct UserLocationAnnotation: View {

    /// Already compensated for the map's own rotation. `nil` when the compass has
    /// not reported yet, in which case no cone is drawn rather than a guessed one.
    let headingRotation: Angle?

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if let headingRotation {
                HeadingCone()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(0.45),
                                Color.accentColor.opacity(0),
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 34
                        )
                    )
                    .frame(width: 68, height: 68)
                    .rotationEffect(headingRotation)
                    // The compass is noisy; without this the cone jitters
                    // constantly while the rider stands still.
                    .animation(.easeOut(duration: 0.25), value: headingRotation)
            }

            Circle()
                .fill(.tint.opacity(0.18))
                .frame(width: 30, height: 30)
                .scaleEffect(isPulsing ? 1.25 : 0.9)
                .opacity(isPulsing ? 0.3 : 0.75)

            Circle()
                .fill(.tint)
                .frame(width: 15, height: 15)
                .overlay {
                    Circle().strokeBorder(.white, lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .accessibilityLabel("Your location")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

/// A wedge opening upward from the centre, so that rotating by a compass heading
/// points it the right way — zero degrees is north, and north is up the screen.
private struct HeadingCone: Shape {

    var spread = Angle.degrees(70)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // SwiftUI angles run clockwise from three o'clock, so straight up is -90.
        let up = Angle.degrees(-90)

        path.move(to: centre)
        path.addArc(
            center: centre,
            radius: radius,
            startAngle: up - spread / 2,
            endAngle: up + spread / 2,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 40) {
        UserLocationAnnotation(headingRotation: .degrees(45))
        UserLocationAnnotation(headingRotation: nil)
    }
    .padding(40)
}
