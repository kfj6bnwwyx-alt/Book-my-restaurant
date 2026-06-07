import Foundation
import MapKit

/// Apple Maps place autocomplete + resolution (no API key, no billing). Powers
/// "search a restaurant and add it" with real coordinates.
@MainActor
@Observable
final class LocalSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address]
        completer.delegate = self
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { results = []; return }
        completer.queryFragment = trimmed
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let updated = completer.results
        Task { @MainActor in self.results = updated }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    struct Resolved { let name: String; let address: String; let coordinate: CLLocationCoordinate2D }

    func resolve(_ completion: MKLocalSearchCompletion) async -> Resolved? {
        await run(MKLocalSearch.Request(completion: completion))
    }

    func resolve(text: String) async -> Resolved? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        return await run(request)
    }

    private func run(_ request: MKLocalSearch.Request) async -> Resolved? {
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let name = item.name ?? request.naturalLanguageQuery ?? "Spot"
        let address = [item.placemark.locality, item.placemark.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        return Resolved(name: name, address: address, coordinate: item.placemark.coordinate)
    }
}
