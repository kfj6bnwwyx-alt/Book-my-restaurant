import SwiftUI

// Filled signal-orange primary action button. Matches the Pencil PrimaryButton.
struct RBPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(RBColor.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RBColor.accent, in: RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Bordered, accent-text button for secondary actions (retry, alternates).
struct RBSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(RBColor.accent)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                    .stroke(RBColor.accent, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RBPrimaryButtonStyle {
    static var rbPrimary: RBPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == RBSecondaryButtonStyle {
    static var rbSecondary: RBSecondaryButtonStyle { .init() }
}
