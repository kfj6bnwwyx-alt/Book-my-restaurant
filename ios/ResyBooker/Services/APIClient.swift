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
}
