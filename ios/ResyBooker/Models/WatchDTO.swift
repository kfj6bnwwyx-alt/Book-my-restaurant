import Foundation
import SwiftUI

/// A standing poll on one venue for a specific date: re-checks on an interval
/// and notifies or auto-books the instant a table in the time window appears
/// (e.g. a cancellation). Matches the server's `_watch_dict`. Resy only.
struct WatchDTO: Codable, Identifiable, Hashable {
    let id: Int
    let pinId: Int?
    let provider: String
    let venueId: String
    let venueName: String
    let day: String                // target "YYYY-MM-DD"
    let partySize: Int
    let earliest: String           // local "HH:mm" window
    let latest: String
    let autobook: Bool
    let notify: Bool
    let intervalSeconds: Int
    let timezone: String
    let active: Bool
    let status: String             // watching | found | booked | expired | error
    let foundDetail: String?
    let lastChecked: String?       // ISO8601, no offset (server UTC)

    enum CodingKeys: String, CodingKey {
        case id, provider, day, earliest, latest, autobook, notify, timezone, active, status
        case pinId = "pin_id"
        case venueId = "venue_id"
        case venueName = "venue_name"
        case partySize = "party_size"
        case intervalSeconds = "interval_seconds"
        case foundDetail = "found_detail"
        case lastChecked = "last_checked"
    }
}

/// Body for POST /watches.
struct WatchCreateRequest: Codable {
    let pinId: Int?
    let provider: String
    let venueId: String
    let venueName: String
    let day: String
    let partySize: Int
    let earliest: String
    let latest: String
    let autobook: Bool
    let notify: Bool
    let intervalSeconds: Int
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case provider, day, earliest, latest, autobook, notify, timezone
        case pinId = "pin_id"
        case venueId = "venue_id"
        case venueName = "venue_name"
        case partySize = "party_size"
        case intervalSeconds = "interval_seconds"
    }
}

/// Body for PATCH /watches/{id}. Only set fields are sent (nil omitted).
/// Setting `active = true` on a found/expired/error watch also resets its
/// status server-side so it polls again.
struct WatchUpdateRequest: Codable {
    var day: String?
    var partySize: Int?
    var earliest: String?
    var latest: String?
    var autobook: Bool?
    var notify: Bool?
    var intervalSeconds: Int?
    var active: Bool?

    enum CodingKeys: String, CodingKey {
        case day, earliest, latest, autobook, notify, active
        case partySize = "party_size"
        case intervalSeconds = "interval_seconds"
    }
}

/// POST /watches/{id}/check — the result of one manual poll.
struct WatchCheckResponse: Codable {
    let status: String             // watching | found | booked | expired | error
    let found: Int?
    let times: [String]?
    let time: String?
    let reservationId: Int?
    let error: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case status, found, times, time, error, note
        case reservationId = "reservation_id"
    }
}

// MARK: - Display helpers

extension WatchDTO {
    /// "Sat · Jul 12" from the target day.
    var dayDisplay: String {
        guard let date = DateFormatter.dayKey.date(from: day) else { return day }
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// "5:00 PM – 10:00 PM" from the HH:mm window bounds.
    var windowDisplay: String {
        "\(WatchDTO.timeDisplay(earliest)) – \(WatchDTO.timeDisplay(latest))"
    }

    /// "Party of 2 · 5:00 PM – 10:00 PM" for the overview card.
    var summaryLine: String {
        "Party of \(partySize) · \(windowDisplay)"
    }

    /// Watch presentation state: a paused watch shows PAUSED regardless of the
    /// last poll result; terminal states keep their own label.
    enum Presentation {
        case watching, paused, found, booked, expired, error
    }

    var presentation: Presentation {
        switch status {
        case "booked": return .booked
        case "found": return .found
        case "expired": return .expired
        case "error": return .error
        default: return active ? .watching : .paused
        }
    }

    var statusLabel: String {
        switch presentation {
        case .watching: return autobook ? "AUTO-BOOK ON" : "WATCHING"
        case .paused: return "PAUSED"
        case .found: return "TABLES FOUND"
        case .booked: return "BOOKED"
        case .expired: return "EXPIRED"
        case .error: return "ERROR"
        }
    }

    var statusIcon: String {
        switch presentation {
        case .watching: return autobook ? "bolt.fill" : "binoculars.fill"
        case .paused: return "pause.fill"
        case .found: return "sparkles"
        case .booked: return "checkmark.circle.fill"
        case .expired: return "clock.badge.xmark"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var statusTint: Color {
        switch presentation {
        case .watching: return RBColor.amber
        case .paused, .expired: return RBColor.textMuted
        case .found, .booked: return RBColor.success
        case .error: return RBColor.red
        }
    }

    var statusSoft: Color {
        switch presentation {
        case .watching: return RBColor.amberSoft
        case .paused, .expired: return RBColor.surface2
        case .found, .booked: return RBColor.successSoft
        case .error: return RBColor.redSoft
        }
    }

    /// "Checked 2m ago" from the server's UTC last_checked, nil if never.
    var lastCheckedDisplay: String? {
        guard let lastChecked else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: lastChecked + "Z")
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: lastChecked + "Z")
        }
        guard let date else { return nil }
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "Checked just now" }
        if s < 3_600 { return "Checked \(s / 60)m ago" }
        if s < 86_400 { return "Checked \(s / 3_600)h ago" }
        return "Checked \(s / 86_400)d ago"
    }

    /// "Every 60s" / "Every 5m" for the info card.
    var intervalDisplay: String {
        intervalSeconds < 60 ? "Every \(intervalSeconds)s"
            : "Every \(intervalSeconds / 60)m"
    }

    /// "17:00" -> "5:00 PM".
    static func timeDisplay(_ hhmm: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: hhmm) else { return hhmm }
        return DateFormatter.summaryTime.string(from: date)
    }
}
