import SwiftUI
import SwiftData

@main
struct ResyBookerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [CachedPin.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            AvailabilityView()
                .tabItem { Label("Tables", systemImage: "fork.knife") }
            PinsView()
                .tabItem { Label("Spots", systemImage: "mappin.and.ellipse") }
        }
    }
}
