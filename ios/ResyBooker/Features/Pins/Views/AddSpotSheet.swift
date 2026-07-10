import SwiftUI
import MapKit
import CoreLocation

/// Add a spot by searching the booking providers directly. Results from
/// /venues/search are real Resy/OpenTable venues, so a picked spot is born
/// linked — no separate Link step. Apple Maps stays as a fallback section for
/// places not on either provider; those add unlinked, like the old flow.
///
/// Searches are biased to a city (persisted): its geocoded center is sent to
/// /venues/search and constrains the Apple Maps completer (regionPriority
/// .required), so same-named venues in other metros don't leak in.
struct AddSpotSheet: View {
    let viewModel: PinsViewModel
    var onAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("addSpotCity") private var city = "New York, NY"
    @AppStorage("addSpotProvider") private var provider = "resy"
    @State private var cityCenter: CLLocationCoordinate2D?
    @State private var resolvingCity = false

    @State private var query = ""
    @State private var search = LocalSearch()
    @State private var providerResults: [VenueSearchResultDTO] = []
    @State private var searching = false
    @State private var serverOutdated = false
    @State private var searchTask: Task<Void, Never>?
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: RBSpacing.md) {
                    cityField
                    providerToggle
                    searchField
                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(RBColor.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                    }
                    resultsList
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

    /// Geocode the typed city → bias provider search + constrain Apple Maps,
    /// then re-run the current query against both.
    private func applyCity() async {
        let q = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { cityCenter = nil; return }
        resolvingCity = true
        let placemark = try? await CLGeocoder().geocodeAddressString(q).first
        resolvingCity = false
        guard let center = placemark?.location?.coordinate else { cityCenter = nil; return }
        cityCenter = center
        search.setCity(center: center)
        queryChanged(query)
    }

    // MARK: Provider toggle

    private var providerToggle: some View {
        HStack(spacing: 0) {
            ForEach(["resy", "opentable"], id: \.self) { p in
                Button {
                    guard provider != p else { return }
                    provider = p
                    providerResults = []
                    queryChanged(query)
                } label: {
                    Text(p.providerDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(provider == p ? RBColor.accentInk : RBColor.textSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(provider == p ? RBColor.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                .fill(RBColor.surface2)
        )
        .padding(.horizontal, 18)
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(RBColor.textMuted)
            TextField("Search a restaurant", text: $query)
                .foregroundStyle(RBColor.textPrimary)
                .autocorrectionDisabled()
                .onChange(of: query) { _, q in queryChanged(q) }
            if searching {
                ProgressView().controlSize(.small).tint(RBColor.accent)
            }
            if !query.isEmpty {
                Button { query = ""; queryChanged("") } label: {
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

    /// Debounced fan-out: Apple Maps autocomplete updates immediately (it has
    /// its own throttling); the provider search waits 300 ms for typing to
    /// settle and cancels any in-flight run.
    private func queryChanged(_ q: String) {
        search.update(query: q)
        searchTask?.cancel()
        error = nil
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            providerResults = []
            searching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runProviderSearch(trimmed)
        }
    }

    private func runProviderSearch(_ q: String) async {
        searching = true
        defer { searching = false }
        do {
            let results = try await viewModel.searchVenues(
                query: q, provider: provider,
                lat: cityCenter?.latitude, lng: cityCenter?.longitude
            )
            guard !Task.isCancelled else { return }
            providerResults = results
            serverOutdated = false
        } catch let apiError as APIError where apiError.isMissingEndpoint {
            providerResults = []
            serverOutdated = true
        } catch is CancellationError {
        } catch {
            providerResults = []
            self.error = error.localizedDescription
        }
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if serverOutdated {
                    outdatedNotice
                } else if !providerResults.isEmpty {
                    RBSectionLabel(title: "BOOKABLE ON \(provider.providerDisplayName.uppercased())")
                    ForEach(providerResults) { venue in
                        resultRow(
                            title: venue.name ?? "Unknown",
                            subtitle: venue.locality ?? "",
                            icon: "checkmark.seal.fill"
                        ) {
                            Task { await addVenue(venue) }
                        }
                    }
                }
                if !trimmedQuery.isEmpty && (!search.results.isEmpty || !providerResults.isEmpty || serverOutdated) {
                    RBSectionLabel(title: "APPLE MAPS — ADDS UNLINKED")
                        .padding(.top, providerResults.isEmpty && !serverOutdated ? 0 : RBSpacing.sm)
                }
                ForEach(Array(search.results.prefix(3).enumerated()), id: \.offset) { _, completion in
                    resultRow(title: completion.title, subtitle: completion.subtitle, icon: "mappin.circle.fill") {
                        Task { await pick(completion) }
                    }
                }
                if !trimmedQuery.isEmpty {
                    resultRow(
                        title: "Add “\(trimmedQuery)”",
                        subtitle: "Use this name as-is, in \(city)",
                        icon: "mappin.circle.fill"
                    ) {
                        Task { await addRaw() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    /// The live server predates /venues/search; Apple Maps below still works.
    private var outdatedNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your booking server is out of date")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RBColor.textPrimary)
            Text("Searching Resy/OpenTable needs a newer server. Rebuild the ResyBooker add-on in Home Assistant (Settings → Add-ons → ResyBooker → Rebuild). Apple Maps below still works.")
                .font(.system(size: 13))
                .foregroundStyle(RBColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard(fill: RBColor.surface2, bordered: false)
    }

    private func resultRow(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(RBColor.accent)
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

    // MARK: Adding

    /// Provider result → born-linked pin. OpenTable results carry no
    /// coordinates; 0/0 marks the pin unlocated so "Resolve missing
    /// locations" can backfill it.
    private func addVenue(_ venue: VenueSearchResultDTO) async {
        adding = true; error = nil
        let ok = await viewModel.addLinkedPin(
            PinCreateRequest(
                name: venue.name ?? trimmedQuery,
                address: venue.locality,
                lat: venue.lat ?? 0,
                lng: venue.lng ?? 0,
                provider: provider,
                venueId: venue.venueId
            )
        )
        if ok {
            onAdded("Spot added — linked to \(provider.providerDisplayName)")
            dismiss()
        } else {
            error = viewModel.errorMessage ?? "Couldn't add the spot."
            adding = false
        }
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
            onAdded("Spot added")
            dismiss()
        } else {
            error = viewModel.errorMessage ?? "Couldn't add the spot."
            adding = false
        }
    }
}
