import SwiftUI

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.26, y: h * 0.54))
        p.addLine(to: CGPoint(x: w * 0.43, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.30))
        return p
    }
}

/// The peak moment: a neutral circle whose green check draws itself on once, with
/// a gentle scale-in and a success haptic. Reserved for confirmed bookings, drop
/// results, and onboarding completion. Calm by design (a draw, not a burst) and
/// faithful to the Vital Green Rule: the circle stays neutral, only the check is green.
struct SuccessCheck: View {
    var size: CGFloat = 84

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var scaled = false

    var body: some View {
        ZStack {
            Circle().fill(RBColor.surface2)
            CheckmarkShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(RBColor.success,
                        style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.5, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .scaleEffect(scaled ? 1 : 0.86)
        .onAppear(perform: play)
    }

    private func play() {
        guard !reduceMotion else {
            drawn = true; scaled = true
            RBHaptics.success()
            return
        }
        withAnimation(.easeOut(duration: 0.28)) { scaled = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.08)) { drawn = true }
        RBHaptics.success()
    }
}

#Preview {
    ZStack {
        RBColor.bg.ignoresSafeArea()
        SuccessCheck()
    }
}
