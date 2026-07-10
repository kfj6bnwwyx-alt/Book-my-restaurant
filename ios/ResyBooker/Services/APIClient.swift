import Foundation

enum APIError: LocalizedError {
    case badStatus(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case let .badStatus(code, body): return "Server \(code): \(body)"
        case let .decoding(msg): return "Decode failed: \(msg)"
        case let .transport(msg): return "Network: \(msg)"
        }
    }

    /// 401 from the server means the X-App-Key is missing or wrong.
    var isUnauthorized: Bool {
        if case .badStatus(401, _) = self { return true }
        return false
    }

    /// A 404 whose body is FastAPI's default unmatched-route response
    /// (`{"detail":"Not Found"}`). This means the running server build predates
    /// the endpoint the app just called — i.e. the server needs a rebuild — as
    /// opposed to a 404 with a custom detail like "pin not found".
    var isMissingEndpoint: Bool {
        if case let .badStatus(404, body) = self { return body.contains("\"Not Found\"") }
        return false
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func request(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        var comps = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(AppConfig.appKey, forHTTPHeaderField: "X-App-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw APIError.transport("no HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw APIError.badStatus(http.statusCode, text)
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    // MARK: - Key check

    enum KeyCheck: Sendable { case ok, unauthorized, unreachable(String) }

    /// Hits an authed endpoint to confirm the current app key is accepted.
    func checkKey() async -> KeyCheck {
        do {
            _ = try await request("/pins")
            return .ok
        } catch let error as APIError {
            return error.isUnauthorized ? .unauthorized : .unreachable(error.errorDescription ?? "Server unreachable")
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    // MARK: - Pins

    func fetchPins() async throws -> [PinDTO] {
        let data = try await request("/pins")
        return try decode([PinDTO].self, data)
    }

    func importPins(geojson: String) async throws -> ImportResponse {
        let body = try encoder.encode(["geojson": geojson])
        let data = try await request("/pins/import", method: "POST", body: body)
        return try decode(ImportResponse.self, data)
    }

    func candidates(pinId: Int, provider: String) async throws -> [VenueCandidateDTO] {
        let data = try await request(
            "/pins/\(pinId)/candidates",
            query: [URLQueryItem(name: "provider", value: provider)]
        )
        return try decode([VenueCandidateDTO].self, data)
    }

    func link(pinId: Int, _ link: LinkRequest) async throws {
        let body = try encoder.encode(link)
        _ = try await request("/pins/\(pinId)/link", method: "POST", body: body)
    }

    func updatePinLocation(pinId: Int, lat: Double, lng: Double, address: String?) async throws {
        let body = try encoder.encode(PinLocationRequest(lat: lat, lng: lng, address: address))
        _ = try await request("/pins/\(pinId)", method: "PATCH", body: body)
    }

    func deletePin(_ id: Int) async throws {
        _ = try await request("/pins/\(id)", method: "DELETE")
    }

    func unlinkPin(_ id: Int) async throws {
        _ = try await request("/pins/\(id)/unlink", method: "POST")
    }

    /// Dismiss a wrong candidate so /candidates never resurfaces it.
    func rejectCandidate(pinId: Int, provider: String, venueId: String) async throws {
        let body = try encoder.encode(["provider": provider, "venue_id": venueId])
        _ = try await request("/pins/\(pinId)/reject", method: "POST", body: body)
    }

    // MARK: - Venue search / search-to-add

    /// Free-text venue search on a provider. lat/lng bias results to a city.
    func searchVenues(
        query: String, provider: String, lat: Double?, lng: Double?
    ) async throws -> [VenueSearchResultDTO] {
        var q = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "provider", value: provider),
        ]
        if let lat { q.append(URLQueryItem(name: "lat", value: String(lat))) }
        if let lng { q.append(URLQueryItem(name: "lng", value: String(lng))) }
        let data = try await request("/venues/search", query: q)
        return try decode([VenueSearchResultDTO].self, data)
    }

    /// Create a pin that arrives already linked (from a search result).
    /// The server dedupes on (provider, venue_id).
    func createLinkedPin(_ req: PinCreateRequest) async throws -> PinDTO {
        let body = try encoder.encode(req)
        let data = try await request("/pins", method: "POST", body: body)
        return try decode(PinDTO.self, data)
    }

    /// Delete every unlinked pin in one call; returns how many were removed.
    func clearUnlinkedPins() async throws -> Int {
        let data = try await request("/pins/clear-unlinked", method: "POST")
        return try decode(ClearUnlinkedResponse.self, data).deleted
    }

    // MARK: - Availability

    func availability(
        day: String,
        partySize: Int,
        time: String = "19:00:00",
        pinId: Int? = nil
    ) async throws -> AvailabilityResponse {
        var q = [
            URLQueryItem(name: "day", value: day),
            URLQueryItem(name: "party_size", value: String(partySize)),
            URLQueryItem(name: "time", value: time),
        ]
        if let pinId { q.append(URLQueryItem(name: "pin_id", value: String(pinId))) }
        let data = try await request("/availability", query: q)
        return try decode(AvailabilityResponse.self, data)
    }

    /// One linked pin across the next `days` days (restaurant-first view).
    func availabilityWindow(
        pinId: Int,
        partySize: Int,
        time: String = "19:00:00",
        days: Int = 14
    ) async throws -> AvailabilityWindowResponse {
        let q = [
            URLQueryItem(name: "pin_id", value: String(pinId)),
            URLQueryItem(name: "party_size", value: String(partySize)),
            URLQueryItem(name: "time", value: time),
            URLQueryItem(name: "days", value: String(days)),
        ]
        let data = try await request("/availability/window", query: q)
        return try decode(AvailabilityWindowResponse.self, data)
    }

    // MARK: - Booking

    func book(_ req: BookRequest) async throws -> BookResponse {
        let body = try encoder.encode(req)
        let data = try await request("/book", method: "POST", body: body)
        return try decode(BookResponse.self, data)
    }

    // MARK: - Drops

    func fetchDrops() async throws -> [DropDTO] {
        let data = try await request("/drops")
        return try decode([DropDTO].self, data)
    }

    func createDrop(_ req: DropCreateRequest) async throws -> DropDTO {
        let body = try encoder.encode(req)
        let data = try await request("/drops", method: "POST", body: body)
        return try decode(DropDTO.self, data)
    }

    func drop(_ id: Int) async throws -> DropDTO {
        let data = try await request("/drops/\(id)")
        return try decode(DropDTO.self, data)
    }

    func updateDrop(_ id: Int, _ req: DropUpdateRequest) async throws -> DropDTO {
        let body = try encoder.encode(req)
        let data = try await request("/drops/\(id)", method: "PATCH", body: body)
        return try decode(DropDTO.self, data)
    }

    func deleteDrop(_ id: Int) async throws {
        _ = try await request("/drops/\(id)", method: "DELETE")
    }

    func dropWindow(_ id: Int, partySize: Int) async throws -> DropWindowResponse {
        let data = try await request(
            "/drops/\(id)/window",
            query: [URLQueryItem(name: "party_size", value: String(partySize))]
        )
        return try decode(DropWindowResponse.self, data)
    }

    func reserve(_ id: Int, _ req: ReserveRequest) async throws -> ReserveResponse {
        let body = try encoder.encode(req)
        let data = try await request("/drops/\(id)/reserve", method: "POST", body: body)
        return try decode(ReserveResponse.self, data)
    }

    // MARK: - Watches

    func fetchWatches() async throws -> [WatchDTO] {
        let data = try await request("/watches")
        return try decode([WatchDTO].self, data)
    }

    func createWatch(_ req: WatchCreateRequest) async throws -> WatchDTO {
        let body = try encoder.encode(req)
        let data = try await request("/watches", method: "POST", body: body)
        return try decode(WatchDTO.self, data)
    }

    func updateWatch(_ id: Int, _ req: WatchUpdateRequest) async throws -> WatchDTO {
        let body = try encoder.encode(req)
        let data = try await request("/watches/\(id)", method: "PATCH", body: body)
        return try decode(WatchDTO.self, data)
    }

    func deleteWatch(_ id: Int) async throws {
        _ = try await request("/watches/\(id)", method: "DELETE")
    }

    /// Trigger one poll right now; the server mutates the watch as a side effect.
    func checkWatch(_ id: Int) async throws -> WatchCheckResponse {
        let data = try await request("/watches/\(id)/check", method: "POST")
        return try decode(WatchCheckResponse.self, data)
    }
}
