import Foundation

extension DateFormatter {
    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "Fri, Jun 12" — the date half of the Tables search summary.
    static let summaryDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "7:00 PM" — the time half of the search summary and slot chips.
    static let summaryTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

enum SlotTime {
    // Resy times come as "2026-06-12 19:00:00"; OpenTable as ISO-ish strings.
    // Return a friendly "7:00 PM" when parseable, else the raw tail.
    static func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let candidates = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"]
        for fmt in candidates {
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: raw) {
                let out = DateFormatter()
                out.dateFormat = "h:mm a"
                return out.string(from: d)
            }
        }
        if let timePart = raw.split(separator: " ").last { return String(timePart) }
        return raw
    }
}
