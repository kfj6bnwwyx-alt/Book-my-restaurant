import Foundation
import SwiftData
import SwiftUI
import CoreLocation

@MainActor
@Observable
final class PinsViewModel {
    var pins: [PinDTO] = []
    var isLoading = false
    var errorMessage: String?
    var showingError = false
    var importSummary: String?

    private let api = APIClient.shared
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var linkedCount: Int { pins.filter { $0.linked }.count }

    /// Spots imported by name (CSV) have no coordinates yet (lat/lng 0).
    var unlocatedCount: Int { pins.filter { $0.lat == 0 && $0.lng == 0 }.count }

    var unlinkedCount: Int { pins.filter { !$0.linked }.count }

    /// Look up coordinates for name-only spots via Apple Maps and patch them on
    /// the server, so they appear on the map and rank better. Returns how many
    /// were resolved.
    func resolveMissingLocations() async -> Int {
        let search = LocalSearch()
        var resolved = 0
        for pin in pins where pin.lat == 0 && pin.lng == 0 {
            if let match = await search.resolve(text: pin.name) {
                do {
                    try await api.updatePinLocation(
                        pinId: pin.id,
                        lat: match.coordinate.latitude,
                        lng: match.coordinate.longitude,
                        address: match.address.isEmpty ? nil : match.address
                    )
                    resolved += 1
                } catch {}
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await load()
        return resolved
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            pins = try await api.fetchPins()
            syncCache()
        } catch {
            fail(error)
        }
    }

    /// Returns the parse result on success (imported / total_parsed), or nil on
    /// failure (with `errorMessage` set). The counts let the import sheet tell the
    /// user exactly what happened: new places added, already-imported, or a file
    /// with no recognizable places.
    func importGeoJSON(_ text: String) async -> ImportResponse? {
        do {
            let resp = try await api.importPins(geojson: text)
            importSummary = "Imported \(resp.imported) of \(resp.totalParsed) places."
            await load()
            return resp
        } catch {
            fail(error)
            return nil
        }
    }

    /// Provider venue search for the add-a-spot sheet. Rethrows so the sheet
    /// can distinguish a stale server (isMissingEndpoint) from other errors.
    func searchVenues(
        query: String, provider: String, lat: Double?, lng: Double?
    ) async throws -> [VenueSearchResultDTO] {
        try await api.searchVenues(query: query, provider: provider, lat: lat, lng: lng)
    }

    /// Add a venue picked from provider search as a born-linked pin.
    func addLinkedPin(_ req: PinCreateRequest) async -> Bool {
        do {
            _ = try await api.createLinkedPin(req)
            await load()
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Delete every unlinked pin in one server call. Returns the deleted
    /// count, or nil on failure (errorMessage is set).
    func clearUnlinked() async -> Int? {
        do {
            let deleted = try await api.clearUnlinkedPins()
            await load()
            return deleted
        } catch {
            fail(error)
            return nil
        }
    }

    func candidates(for pin: PinDTO, provider: String) async -> [VenueCandidateDTO] {
        do {
            return try await api.candidates(pinId: pin.id, provider: provider)
        } catch {
            fail(error)
            return []
        }
    }

    func link(pin: PinDTO, to candidate: VenueCandidateDTO, provider: String) async {
        do {
            try await api.link(
                pinId: pin.id,
                LinkRequest(
                    provider: provider,
                    venueId: candidate.venueId,
                    linkedName: candidate.name
                )
            )
            await load()
        } catch {
            fail(error)
        }
    }

    /// Remove an imported pin entirely (prune a wrong/junk import).
    func deletePin(_ pin: PinDTO) async {
        do {
            try await api.deletePin(pin.id)
            pins.removeAll { $0.id == pin.id }
            let cached = (try? modelContext.fetch(FetchDescriptor<CachedPin>())) ?? []
            for c in cached where c.serverId == pin.id { modelContext.delete(c) }
            try? modelContext.save()
        } catch {
            fail(error)
        }
    }

    /// Undo a venue link without deleting the pin.
    func unlinkPin(_ pin: PinDTO) async {
        do {
            try await api.unlinkPin(pin.id)
            await load()
        } catch {
            fail(error)
        }
    }

    /// Dismiss a wrong candidate so it never resurfaces for this pin.
    func rejectCandidate(pin: PinDTO, candidate: VenueCandidateDTO, provider: String) async {
        do {
            try await api.rejectCandidate(pinId: pin.id, provider: provider, venueId: candidate.venueId)
        } catch {
            fail(error)
        }
    }

    private func syncCache() {
        let existing = (try? modelContext.fetch(FetchDescriptor<CachedPin>())) ?? []
        let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for dto in pins {
            if let cached = byId[dto.id] {
                cached.apply(dto)
            } else {
                modelContext.insert(
                    CachedPin(
                        serverId: dto.id, name: dto.name, address: dto.address,
                        lat: dto.lat, lng: dto.lng, provider: dto.provider,
                        venueId: dto.venueId, linked: dto.linked
                    )
                )
            }
        }
        try? modelContext.save()
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
