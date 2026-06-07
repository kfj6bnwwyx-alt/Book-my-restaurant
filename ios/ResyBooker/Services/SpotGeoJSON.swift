import Foundation

/// Builds the one-feature GeoJSON the import endpoint accepts, for adding a
/// single spot (manual add, or a shared place).
enum SpotGeoJSON {
    static func oneFeature(name: String, address: String = "", lat: Double, lng: Double) -> String {
        var location: [String: Any] = ["Business Name": name]
        if !address.isEmpty { location["Address"] = address }
        let feature: [String: Any] = [
            "type": "Feature",
            "geometry": ["type": "Point", "coordinates": [lng, lat]],
            "properties": ["Location": location],
        ]
        let root: [String: Any] = ["type": "FeatureCollection", "features": [feature]]
        let data = (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
