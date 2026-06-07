import Foundation
import SwiftData
import SwiftUI

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

    @discardableResult
    func importGeoJSON(_ text: String) async -> Bool {
        do {
            let resp = try await api.importPins(geojson: text)
            importSummary = "Imported \(resp.imported) of \(resp.totalParsed) places."
            await load()
            return true
        } catch {
            fail(error)
            return false
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
