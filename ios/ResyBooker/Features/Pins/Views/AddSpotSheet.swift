import SwiftUI
import CoreLocation

/// Add a single spot by hand. Forward-geocodes the name/address on device so the
/// pin has coordinates for venue matching, then saves it through the existing
/// import endpoint (a one-feature GeoJSON) — no server change needed.
struct AddSpotSheet: View {
    let viewModel: PinsViewModel
    var onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RBSpacing.lg) {
                        field("Name", placeholder: "Restaurant name", text: $name)
                        field("Address or city (optional)", placeholder: "e.g. 5 Greenwich Ave, New York", text: $address)
                        Text("We look up the location on device so the spot can match Resy and OpenTable.")
                            .font(.system(size: 13))
                            .foregroundStyle(RBColor.textSecondary)
                        if let error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(RBColor.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(saving ? "Adding…" : "Add spot", action: save)
                            .buttonStyle(.rbPrimary)
                            .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .padding(.top, RBSpacing.xs)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Add a spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(RBColor.accent)
                }
            }
        }
        .tint(RBColor.accent)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(RBColor.textSecondary)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundStyle(RBColor.textPrimary)
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .fill(RBColor.surface2)
                )
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        error = nil
        Task {
            let coord = await geocode(name: trimmedName, address: address)
            let geojson = SpotGeoJSON.oneFeature(name: trimmedName, address: address, lat: coord.latitude, lng: coord.longitude)
            if await viewModel.importGeoJSON(geojson) != nil {
                onAdded()
                dismiss()
            } else {
                error = viewModel.errorMessage ?? "Couldn't add the spot."
                saving = false
            }
        }
    }

    /// Forward-geocode; fall back to NYC (the Resy search default) if it can't resolve.
    private func geocode(name: String, address: String) async -> CLLocationCoordinate2D {
        let query = address.isEmpty ? name : "\(name), \(address)"
        if let placemark = try? await CLGeocoder().geocodeAddressString(query).first,
           let location = placemark.location {
            return location.coordinate
        }
        return CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.006)
    }
}
