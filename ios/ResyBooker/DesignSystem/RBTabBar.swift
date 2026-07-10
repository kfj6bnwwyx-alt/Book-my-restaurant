import SwiftUI

/// The three destinations, matching the Pencil `component/TabBar`.
enum RBTab: String, CaseIterable, Identifiable {
    case tables, drops, spots
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tables: "Tables"
        case .drops: "Drops"
        case .spots: "Spots"
        }
    }

    var icon: String {
        switch self {
        case .tables: "fork.knife"
        case .drops: "calendar.badge.clock"
        case .spots: "mappin.and.ellipse"
        }
    }
}

/// Floating frosted capsule, inset from the edges. Selected tab carries an
/// accent-soft pill with an orange icon and label; inactive tabs are muted and
/// unfilled. Shadow is reserved for genuinely floating chrome (see Elevation).
struct RBTabBar: View {
    /// Capsule height (48pt buttons + RBSpacing.xs top/bottom padding). RootView
    /// reserves this much bottom space so content never hides behind the bar.
    static let height: CGFloat = 48 + RBSpacing.xs * 2

    @Binding var selection: RBTab

    var body: some View {
        HStack(spacing: RBSpacing.xs) {
            ForEach(RBTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(RBSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(RBColor.surface2.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(RBColor.border, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.33), radius: 15, x: 0, y: 10)
        .padding(.horizontal, RBSpacing.lg)
    }

    private func tabButton(_ tab: RBTab) -> some View {
        let selected = tab == selection
        return Button {
            if selection != tab {
                RBHaptics.selection()
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? RBColor.accent : RBColor.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(selected ? RBColor.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        RBColor.bg.ignoresSafeArea()
        RBTabBar(selection: .constant(.tables))
    }
}
