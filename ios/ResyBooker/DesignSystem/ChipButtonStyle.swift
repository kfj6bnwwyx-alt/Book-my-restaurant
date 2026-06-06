import SwiftUI

/// Time and day chips. A quick scale dip on press plus a selection haptic make
/// multi-selecting slots in the drop grid feel tactile. Selected chips flip to
/// Signal Orange (the user's action); unselected sit in surface-2. This is the
/// one repeated interaction worth making satisfying, since picking slots is the
/// core gesture of the drop grid.
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? RBColor.accentInk : RBColor.textPrimary)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? RBColor.accent : RBColor.surface2)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { RBHaptics.selection() }
            }
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static func rbChip(selected: Bool) -> ChipButtonStyle { .init(isSelected: selected) }
}

/// Drop-in for the closing countdown / counts: smooth digit roll instead of a hard swap.
/// Usage: Text(remaining).monospacedDigit().contentTransition(.numericText())
///        then animate the value change with .easeOut.
extension Text {
    func rbTicking() -> some View {
        self.monospacedDigit().contentTransition(.numericText())
    }
}

#Preview {
    ZStack {
        RBColor.bg.ignoresSafeArea()
        HStack(spacing: 8) {
            Button("7:00") {}.buttonStyle(.rbChip(selected: false))
            Button("7:30") {}.buttonStyle(.rbChip(selected: true))
        }
    }
}
