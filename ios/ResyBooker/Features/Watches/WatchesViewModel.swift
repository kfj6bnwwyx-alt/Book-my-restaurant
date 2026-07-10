import Foundation
import SwiftUI

@MainActor
@Observable
final class WatchesViewModel {
    enum State { case idle, loading, loaded, failed }

    var state: State = .idle
    var watches: [WatchDTO] = []
    var errorMessage: String?
    var isAuthError = false

    private let api = APIClient.shared

    func load() async {
        state = .loading
        isAuthError = false
        errorMessage = nil
        do {
            watches = try await api.fetchWatches()
            state = .loaded
        } catch {
            errorMessage = error.localizedDescription
            isAuthError = (error as? APIError)?.isUnauthorized ?? false
            state = .failed
        }
    }

    /// Replace one watch in place after a PATCH / manual check, keeping order.
    func replace(_ updated: WatchDTO) {
        if let i = watches.firstIndex(where: { $0.id == updated.id }) {
            watches[i] = updated
        }
    }

    func delete(_ watch: WatchDTO) async {
        do {
            try await api.deleteWatch(watch.id)
            watches.removeAll { $0.id == watch.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
