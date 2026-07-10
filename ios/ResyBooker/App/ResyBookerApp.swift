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

