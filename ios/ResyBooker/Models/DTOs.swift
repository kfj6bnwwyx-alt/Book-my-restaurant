import Foundation

// Wire types matching the server's JSON. Plain structs, no persistence.

struct PinDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let address: String?
    let lat: Double
    let lng: Double
    let provider: String?
    let venueId: String?
    let linked: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, address, lat, lng, provider, linked
        case venueId = "venue_id"
    }
}

struct VenueCandidateDTO: Codable, Identifiable, Hashable {
    var id: String { venueId }
    let score: Double
    let venueId: String
    let name: String?
    let locality: String?

    enum CodingKeys: String, CodingKey {
        case score, name, locality
        case venueId = "venue_id"
    }
}

struct SlotDTO: Codable, Hashable {
    // Resy slots carry config_token + time; OpenTable carry time + slot_hash.
    let configToken: String?
    let time: String?
    let slotHash: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case time, type
        case configToken = "config_token"
        case slotHash = "slot_hash"
    }
}

struct VenueAvailabilityDTO: Codable, Identifiable, Hashable {
    var id: Int { pinId }
    let pinId: Int
    let name: String
    let provider: String?
    let venueId: String?
    let slots: [SlotDTO]
    let available: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case name, provider, slots, available, error
        case pinId = "pin_id"
        case venueId = "venue_id"
    }
}

struct AvailabilityResponse: Codable {
    let day: String
    let partySize: Int
    let results: [VenueAvailabilityDTO]

    enum CodingKeys: String, CodingKey {
        case day, results
        case partySize = "party_size"
    }
}

/// GET /availability/window — one restaurant across the next N days. Reuses
/// DropDayDTO ({day, slots, available}) so the per-restaurant view and the drop
/// grid render days the same way.
struct AvailabilityWindowResponse: Codable {
    let pinId: Int
    let name: String
    let provider: String?
    let venueId: String?
    let partySize: Int
    let days: Int
    let results: [DropDayDTO]

    enum CodingKeys: String, CodingKey {
        case name, provider, days, results
        case pinId = "pin_id"
        case venueId = "venue_id"
        case partySize = "party_size"
    }
}

struct ImportResponse: Codable {
    let imported: Int
    let totalParsed: Int

    enum CodingKeys: String, CodingKey {
        case imported
        case totalParsed = "total_parsed"
    }
}

struct LinkRequest: Codable {
    let provider: String
    let venueId: String
    let linkedName: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case venueId = "venue_id"
        case linkedName = "linked_name"
    }
}

struct PinLocationRequest: Codable {
    let lat: Double
    let lng: Double
    let address: String?
}

/// One row from GET /venues/search — a bookable venue on Resy/OpenTable.
/// Resy results carry coordinates; OpenTable's don't (lat/lng nil).
struct VenueSearchResultDTO: Codable, Identifiable, Hashable {
    var id: String { venueId }
    let venueId: String
    let name: String?
    let locality: String?
    let lat: Double?
    let lng: Double?

    enum CodingKeys: String, CodingKey {
        case name, locality, lat, lng
        case venueId = "venue_id"
    }
}

/// POST /pins — create a pin already linked to a provider venue.
struct PinCreateRequest: Codable {
    let name: String
    let address: String?
    let lat: Double
    let lng: Double
    let provider: String
    let venueId: String

    enum CodingKeys: String, CodingKey {
        case name, address, lat, lng, provider
        case venueId = "venue_id"
    }
}

struct ClearUnlinkedResponse: Codable {
    let deleted: Int
}

struct BookRequest: Codable {
    let pinId: Int?
    let venueId: String
    let venueName: String
    let day: String
    let partySize: Int
    let configToken: String

    enum CodingKeys: String, CodingKey {
        case day
        case pinId = "pin_id"
        case venueId = "venue_id"
        case venueName = "venue_name"
        case partySize = "party_size"
        case configToken = "config_token"
    }
}

struct BookResponse: Codable {
    let ok: Bool
    let resyToken: String?
    let reservationId: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case resyToken = "resy_token"
        case reservationId = "reservation_id"
    }
}
