import SwiftUI
import MapKit

/// Add a spot by searching Apple Maps (autocomplete, no API key). Picking a
/// result gives an exact name + coordinates; "Add as-is" falls back to a plain
/// search/geocode. Saves through the existing import endpoint (no server change).
struct AddSpotSheet: View {
    let viewModel: PinsViewModel
    var onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var search = LocalSearch()
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: RBSpacing.md) {
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
                                resultRow(title: "Add “\(trimmedQuery)”", subtitle: "Use this name as-is") {
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
        }
        .tint(RBColor.accent)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

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
            await add(name: trimmedQuery, address: "", lat: 40.7128, lng: -74.006)
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
