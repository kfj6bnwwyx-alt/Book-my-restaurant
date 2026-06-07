import UIKit
import Social
import UniformTypeIdentifiers

/// Share a place into ResyBooker. Pulls the name (and coordinates when the link
/// carries them, e.g. Apple Maps `?ll=`), pre-fills the editable name, and on
/// Post queues it in the shared App Group for the app to import.
class ShareViewController: SLComposeServiceViewController {
    private var coordinate: (lat: Double, lng: Double)?

    override func presentationAnimationDidFinish() {
        placeholder = "Restaurant name"
        loadSharedPlace()
    }

    override func isContentValid() -> Bool {
        !(contentText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    override func didSelectPost() {
        let name = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            PendingSpots.append(PendingSpot(name: name, lat: coordinate?.lat, lng: coordinate?.lng))
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! { [] }

    // MARK: Extract the shared place

    private func loadSharedPlace() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else { return }

        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] value, _ in
                let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
                if let url { DispatchQueue.main.async { self?.apply(url: url) } }
            }
            return
        }
        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] value, _ in
                if let text = value as? String {
                    DispatchQueue.main.async { self?.prefillName(text) }
                }
            }
        }
    }

    private func apply(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value }

        // Apple Maps carries coordinates: ?ll=lat,lng (or coordinate=, sll=)
        if let ll = value("ll") ?? value("coordinate") ?? value("sll") {
            let parts = ll.split(separator: ",")
            if parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
                coordinate = (lat, lng)
            }
        }
        let name = value("q") ?? value("name") ?? value("address") ?? placeName(from: url) ?? url.host
        if let name { prefillName(name) }
    }

    /// e.g. ".../maps/place/Casa+Mono/data=..." -> "Casa Mono"
    private func placeName(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "place"), i + 1 < parts.count else { return nil }
        let raw = parts[i + 1].removingPercentEncoding ?? parts[i + 1]
        let cleaned = raw.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func prefillName(_ name: String) {
        if (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.text = name
        }
    }
}
