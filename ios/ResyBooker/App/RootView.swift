import SwiftUI
import SwiftData

/// App shell: a dark surface with the three feature screens and a floating
/// capsule tab bar overlaid at the bottom.
///
/// All three tab views stay alive in a ZStack (only the selected one is visible
/// and interactive), so each tab's @State — search results, scroll position —
/// is preserved across switches, the way the system TabView behaves. Content
/// reserves space for the bar via a bottom safe-area inset tied to the bar's
/// real height so nothing hides behind it.
struct RootView: View {
    @State private var tab: RBTab = .tables

    var body: some View {
        ZStack(alignment: .bottom) {
            RBColor.bg.ignoresSafeArea()

            ZStack {
                tabContent(.tables) { AvailabilityView() }
                tabContent(.drops) { DropsView() }
                tabContent(.spots) { PinsView() }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: RBTabBar.height + RBSpacing.sm)
            }

            RBTabBar(selection: $tab)
        }
        .tint(RBColor.accent)
        .preferredColorScheme(.dark)
    }

    /// Keeps each tab in the hierarchy (state preserved) while hiding the
    /// inactive ones from sight, hit-testing, and assistive tech.
    @ViewBuilder
    private func tabContent<Content: View>(
        _ which: RBTab, @ViewBuilder _ content: () -> Content
    ) -> some View {
        let active = (tab == which)
        content()
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [CachedPin.self], inMemory: true)
}
