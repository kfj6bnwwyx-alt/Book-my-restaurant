import SwiftUI

/// Recoverable error state: a red glyph, what happened, and a retry affordance.
/// Use inside a screen body when a fetch fails, not as a blocking alert.
struct InlineErrorView: View {
    let title: String
    let message: String
    var retryTitle: String = "Try again"
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: RBSpacing.lg) {
            ZStack {
                Circle().fill(RBColor.redSoft)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(RBColor.red)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: RBSpacing.xs) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(RBColor.textPrimary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 300)

            if let retry {
                Button(action: retry) {
                    Label(retryTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.rbSecondary)
                .padding(.top, RBSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    ZStack {
        RBColor.bg.ignoresSafeArea()
        InlineErrorView(
            title: "Couldn't reach the server",
            message: "Your booking server didn't respond. Check that it's running, then try again.",
            retry: {}
        )
    }
}
