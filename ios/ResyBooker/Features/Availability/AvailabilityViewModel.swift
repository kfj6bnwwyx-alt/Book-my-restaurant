import Foundation
import SwiftUI

@MainActor
@Observable
final class AvailabilityViewModel {
    enum State { case idle, loading, loaded, failed }

    var day: Date = .now
    var partySize: Int = 2
    var time: Date = Calendar.current.date(
        bySettingHour: 19, minute: 0, second: 0, of: .now
    ) ?? .now

    var state: State = .idle
    var results: [VenueAvailabilityDTO] = []
    var errorMessage: String?
    var showingError = false

    private let api = APIClient.shared

    var availableResults: [VenueAvailabilityDTO] { results.filter { $0.available } }
    var unavailableResults: [VenueAvailabilityDTO] { results.filter { !$0.available } }

    func search() async {
        state = .loading
        let dayStr = DateFormatter.dayKey.string(from: day)
        let timeStr = timeString()
        do {
            let resp = try await api.availability(
                day: dayStr, partySize: partySize, time: timeStr
            )
            results = resp.results
            state = .loaded
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            state = .failed
        }
    }

    private func timeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: time)
    }
}
