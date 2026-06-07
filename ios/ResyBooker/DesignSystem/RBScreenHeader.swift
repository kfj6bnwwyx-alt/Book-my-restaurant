import SwiftUI

/// The constant 28/700 screen title (and optional subtitle), held uniform across
/// primary screens so the app reads as one tool.
struct RBScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Uppercase section overline with a trailing count, e.g. "AVAILABLE  2 spots".
/// The count carries the signal color (green for available, muted otherwise).
struct RBSectionLabel: View {
    let title: String
    var count: String? = nil
    var countColor: Color = RBColor.textMuted

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(RBColor.textMuted)
            Spacer()
            if let count {
                Text(count)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(countColor)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, RBSpacing.xs)
    }
}
