import Foundation
import SwiftData

// Local cache of pins so the map/list renders offline and link state persists.
// Availability is always fetched live from the server, never cached here.
@Model
final class CachedPin {
    @Attribute(.unique) var serverId: Int
    var name: String
    var address: String?
    var lat: Double
    var lng: Double
    var provider: String?
    var venueId: String?
    var linked: Bool
    var updatedAt: Date

    init(
        serverId: Int,
        name: String,
        address: String? = nil,
        lat: Double,
        lng: Double,
        provider: String? = nil,
        venueId: String? = nil,
        linked: Bool = false
    ) {
        self.serverId = serverId
        self.name = name
        self.address = address
        self.lat = lat
        self.lng = lng
        self.provider = provider
        self.venueId = venueId
        self.linked = linked
        self.updatedAt = .now
    }

    func apply(_ dto: PinDTO) {
        name = dto.name
        address = dto.address
        lat = dto.lat
        lng = dto.lng
        provider = dto.provider
        venueId = dto.venueId
        linked = dto.linked
        updatedAt = .now
    }
}
