import SwiftUI
import MapKit
import CoreLocation

/// Add a spot by searching Apple Maps (autocomplete, no API key). Picking a
/// result gives an exact name + coordinates; "Add as-is" falls back to a plain
/// search/geocode. Saves through the existing import endpoint (no server change).
///
/// Searches are constrained to a city (persisted across launches). Resy is
/// NYC-centric, but you can point it at any metro — without the constraint,
/// autocomplete matches same-named restaurants in the wrong city.
struct AddSpotSheet: View {
    let viewModel: PinsViewModel
    var onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("addSpotCity") private var city = "New York, NY"
    @State private var cityCenter: CLLocationCoordinate2D?
    @State private var resolvingCity = false

    @State private var query = ""
    @State private var search = LocalSearch()
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: RBSpacing.md) {
                    cityField
                    searchField
                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(RBColor.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                    }
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(search.results.enumerated()), id: \.offset) { _, completion in
                                resultRow(title: completion.title, subtitle: completion.subtitle) {
                                    Task { await pick(completion) }
                                }
                            }
                            if !trimmedQuery.isEmpty {
                                resultRow(title: "Add “\(trimmedQuery)”", subtitle: "Use this name as-is, in \(city)") {
                                    Task { await addRaw() }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }
                }
                .padding(.top, RBSpacing.sm)
                .disabled(adding)
                if adding {
                    ProgressView().controlSize(.large).tint(RBColor.accent)
                }
            }
            .navigationTitle("Add a spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(RBColor.accent)
                }
            }
            .task { await applyCity() }
        }
        .tint(RBColor.accent)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: City constraint

    private var cityField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SEARCHING IN")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RBColor.textMuted)
                .padding(.horizontal, 18)
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(RBColor.accent)
                TextField("City (e.g. New York, NY)", text: $city)
                    .foregroundStyle(RBColor.textPrimary)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await applyCity() } }
                if resolvingCity {
                    ProgressView().controlSize(.small)
                } else if cityCenter != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RBColor.success)
                } else {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(RBColor.amber)
                }
            }
            .font(.system(size: 16))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .rbCard(fill: RBColor.surface2, bordered: false)
            .padding(.horizontal, 18)
        }
    }

    /// Geocode the typed city → set the search region, then refresh results.
    private func applyCity() async {
        let q = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { cityCenter = nil; return }
        resolvingCity = true
        let placemark = try? await CLGeocoder().geocodeAddressString(q).first
        resolvingCity = false
        guard let center = placemark?.location?.coordinate else { cityCenter = nil; return }
        cityCenter = center
        search.setCity(center: center)
        search.update(query: query)   // re-run the current query within the new city
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(RBColor.textMuted)
            TextField("Search a restaurant", text: $query)
                .foregroundStyle(RBColor.textPrimary)
                .autocorrectionDisabled()
                .onChange(of: query) { _, q in search.update(query: q) }
            if !query.isEmpty {
                Button { query = ""; search.update(query: "") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(RBColor.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16))
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .rbCard(fill: RBColor.surface2, bordered: false)
        .padding(.horizontal, 18)
    }

    private func resultRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(RBColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(RBColor.textPrimary).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12.5)).foregroundStyle(RBColor.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(RBColor.textMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rbCard(radius: RBRadius.small)
        }
        .buttonStyle(.plain)
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        adding = true; error = nil
        if let resolved = await search.resolve(completion) {
            await add(name: resolved.name, address: resolved.address,
                      lat: resolved.coordinate.latitude, lng: resolved.coordinate.longitude)
        } else {
            error = "Couldn't resolve that place."; adding = false
        }
    }

    private func addRaw() async {
        adding = true; error = nil
        if let resolved = await search.resolve(text: trimmedQuery) {
            await add(name: resolved.name, address: resolved.address,
                      lat: resolved.coordinate.latitude, lng: resolved.coordinate.longitude)
        } else {
            // No match in the chosen city — keep the name, anchor on the city centre
            // so it still lands on the map (falls back to NYC if the city is unset).
            await add(name: trimmedQuery, address: city,
                      lat: cityCenter?.latitude ?? 40.7128,
                      lng: cityCenter?.longitude ?? -74.006)
        }
    }

    private func add(name: String, address: String, lat: Double, lng: Double) async {
        let geojson = SpotGeoJSON.oneFeature(name: name, address: address, lat: lat, lng: lng)
        if await viewModel.importGeoJSON(geojson) != nil {
            onAdded()
            dismiss()
        } else {
            error = viewModel.errorMessage ?? "Couldn't add the spot."
            adding = false
        }
    }
}
