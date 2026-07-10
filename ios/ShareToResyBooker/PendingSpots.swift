import Foundation

/// A place shared into the app, awaiting import. Written by the share extension,
/// drained by the app. (Duplicated in the app target — kept tiny on purpose.)
struct PendingSpot: Codable {
    let name: String
    let lat: Double?
    let lng: Double?
}

enum PendingSpots {
    /// Must match the App Group added to BOTH targets' capabilities.
    static let appGroup = "group.house-connect.Book-my-restaurant"
    private static let fileName = "pending-spots.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func all() -> [PendingSpot] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PendingSpot].self, from: data)) ?? []
    }

    static func append(_ spot: PendingSpot) {
        var list = all()
        list.append(spot)
        save(list)
    }

    static func save(_ list: [PendingSpot]) {
        guard let fileURL else { return }
        try? JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
    }

    static func clear() { save([]) }
}
