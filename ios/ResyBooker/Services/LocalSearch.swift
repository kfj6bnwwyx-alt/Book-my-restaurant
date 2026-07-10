import Foundation
import MapKit
import CoreLocation

/// Apple Maps place autocomplete + resolution (no API key, no billing). Powers
/// "search a restaurant and add it" with real coordinates.
///
/// Searches are constrained to a city region (`regionPriority = .required`, iOS
/// 18+). Without it, autocomplete returns every "Carbone" / "Lilia" on earth and
/// the wrong coordinates leak in. Set the city with `setCity(center:)`.
@MainActor
@Observable
final class LocalSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    private(set) var region: MKCoordinateRegion?

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address]
        completer.delegate = self
    }

    /// Hard-constrain results to one city. `.required` makes the region a filter,
    /// not just a bias — "Carbone" resolves to the one in *this* city only.
    func setCity(center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance = 30_000) {
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        self.region = region
        completer.region = region
        completer.regionPriority = .required
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
        if let region {
            request.region = region
            request.regionPriority = .required
        }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let name = item.name ?? request.naturalLanguageQuery ?? "Spot"
        let address = [item.placemark.locality, item.placemark.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        return Resolved(name: name, address: address, coordinate: item.placemark.coordinate)
    }
}
