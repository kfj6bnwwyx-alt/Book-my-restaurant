import Foundation
import SwiftUI

@MainActor
@Observable
final class DropsViewModel {
    enum State { case idle, loading, loaded, failed }

    var state: State = .idle
    var drops: [DropDTO] = []
    var errorMessage: String?
    var isAuthError = false

    private let api = APIClient.shared

    func load() async {
        state = .loading
        isAuthError = false
        errorMessage = nil
        do {
            drops = try await api.fetchDrops()
            state = .loaded
        } catch {
            errorMessage = error.localizedDescription
            isAuthError = (error as? APIError)?.isUnauthorized ?? false
            state = .failed
        }
    }
}
