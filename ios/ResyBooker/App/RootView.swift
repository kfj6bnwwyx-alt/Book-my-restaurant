import SwiftUI
import SwiftData
import CoreLocation

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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

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
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showingOnboarding = false
            }
        }
        .onAppear {
            // First run only. A device that already has a key predates the
            // onboarding flow — mark it done instead of re-teaching.
            guard !hasCompletedOnboarding else { return }
            if AppConfig.hasAppKey {
                hasCompletedOnboarding = true
            } else {
                showingOnboarding = true
            }
        }
        .task { await Self.importPendingShares() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await Self.importPendingShares() } }
        }
    }

    /// Drain places shared in via the extension. Geocodes any without
    /// coordinates, imports them, and keeps any that fail for the next launch.
    private static func importPendingShares() async {
        let pending = PendingSpots.all()
        guard !pending.isEmpty, AppConfig.hasAppKey else { return }
        var remaining: [PendingSpot] = []
        for spot in pending {
            let lat: Double
            let lng: Double
            if let la = spot.lat, let lo = spot.lng {
                (lat, lng) = (la, lo)
            } else if let location = try? await CLGeocoder().geocodeAddressString(spot.name).first?.location {
                (lat, lng) = (location.coordinate.latitude, location.coordinate.longitude)
            } else {
                (lat, lng) = (40.7128, -74.006)
            }
            let geojson = SpotGeoJSON.oneFeature(name: spot.name, lat: lat, lng: lng)
            do { _ = try await APIClient.shared.importPins(geojson: geojson) }
            catch { remaining.append(spot) }
        }
        PendingSpots.save(remaining)
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
