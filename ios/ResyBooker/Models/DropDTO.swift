import Foundation

/// A venue that releases reservations on a schedule. Matches the server's
/// `_drop_dict` (drop fields + nested autobook + computed status).
struct DropDTO: Codable, Identifiable, Hashable {
    let id: Int
    let pinId: Int?
    let provider: String
    let venueId: String
    let venueName: String
    let cadence: String            // daily | weekly | biweekly | monthly
    let releaseWeekday: Int?
    let releaseDom: Int?
    let releaseTime: String        // local "HH:mm"
    let anchorDate: String?
    let windowDays: Int
    let timezone: String
    let watching: Bool
    let autobookEnabled: Bool
    let autobook: AutobookDTO

    // Computed status from the server
    let open: Bool
    let status: String             // "open" | "upcoming"
    let nextRelease: String        // ISO8601
    let opensInSeconds: Int
    let windowStart: String        // "YYYY-MM-DD"
    let windowEnd: String          // "YYYY-MM-DD"

    enum CodingKeys: String, CodingKey {
        case id, provider, cadence, timezone, watching, autobook, open, status
        case pinId = "pin_id"
        case venueId = "venue_id"
        case venueName = "venue_name"
        case releaseWeekday = "release_weekday"
        case releaseDom = "release_dom"
        case releaseTime = "release_time"
        case anchorDate = "anchor_date"
        case windowDays = "window_days"
        case autobookEnabled = "autobook_enabled"
        case nextRelease = "next_release"
        case opensInSeconds = "opens_in_seconds"
        case windowStart = "window_start"
        case windowEnd = "window_end"
    }
}

struct AutobookDTO: Codable, Hashable {
    let partySize: Int?
    let days: String?
    let earliest: String?
    let latest: String?
    let max: Int?
    let priority: String?
    let notifyOnFail: Bool?

    enum CodingKeys: String, CodingKey {
        case days, earliest, latest, max, priority
        case partySize = "party_size"
        case notifyOnFail = "notify_on_fail"
    }
}

extension DropDTO {
    /// "Daily" / "Weekly" / "Every 2 weeks" / "Monthly".
    var cadenceLabel: String {
        switch cadence.lowercased() {
        case "daily": "Daily"
        case "weekly": "Weekly"
        case "biweekly": "Every 2 weeks"
        case "monthly": "Monthly"
        default: cadence.capitalized
        }
    }

    /// "Every 2 weeks · 12:00 PM" for the overview card.
    var scheduleLine: String {
        "\(cadenceLabel) · \(releaseTimeDisplay)"
    }

    /// "12:00" -> "12:00 PM".
    var releaseTimeDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: releaseTime) else { return releaseTime }
        return DateFormatter.summaryTime.string(from: date)
    }

    /// Parsed next-release instant for a live countdown (server sends ISO8601
    /// with a timezone offset).
    var nextReleaseDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let date = f.date(from: nextRelease) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: nextRelease)
    }

    /// "14 days (Jun 18 – Jul 1)" from the window bounds.
    var windowLine: String {
        let label = "\(windowDays) days"
        let from = DropDTO.shortDate(windowStart)
        let to = DropDTO.shortDate(windowEnd)
        if let from, let to { return "\(label) (\(from) – \(to))" }
        return label
    }

    private static func shortDate(_ ymd: String) -> String? {
        guard let date = DateFormatter.dayKey.date(from: ymd) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// Short countdown like "2d", "4h", "17m", "soon" for the status badge.
    var opensInShort: String {
        let s = opensInSeconds
        if s <= 0 { return "now" }
        let days = s / 86_400
        if days >= 1 { return "\(days)d" }
        let hours = s / 3_600
        if hours >= 1 { return "\(hours)h" }
        let mins = max(1, s / 60)
        return "\(mins)m"
    }
}
