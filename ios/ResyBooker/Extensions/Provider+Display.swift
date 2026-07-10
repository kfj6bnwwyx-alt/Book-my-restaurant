import Foundation

extension String {
    /// Human label for a provider id: "resy" -> "Resy", "opentable" -> "OpenTable".
    var providerDisplayName: String {
        switch lowercased() {
        case "resy": "Resy"
        case "opentable": "OpenTable"
        default: capitalized
        }
    }
}
