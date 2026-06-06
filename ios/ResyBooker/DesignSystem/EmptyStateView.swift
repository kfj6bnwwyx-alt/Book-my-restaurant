import SwiftUI

/// Teaching empty state: a neutral icon, a heading, a supporting line, and an
/// optional primary action. Used for "no linked spots", "no drops tracked", etc.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: RBSpacing.lg) {
            ZStack {
                Circle()
                    .fill(RBColor.surface)
                    .overlay(Circle().stroke(RBColor.border, lineWidth: 1))
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(RBColor.textMuted)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: RBSpacing.xs) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(RBColor.textPrimary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.rbPrimary)
                    .frame(maxWidth: 240)
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
        EmptyStateView(
            systemImage: "mappin.and.ellipse",
            title: "No linked spots yet",
            message: "Link your saved spots to Resy or OpenTable, then search for tables here.",
            actionTitle: "Go to Spots",
            action: {}
        )
    }
}
