import SwiftUI

/// Tables tab: one screen that checks Resy + OpenTable across every linked spot
/// for a date, time, and party, then books a Resy slot in one tap. Matches the
/// Pencil Tables screens (results, empty, loading, none-available, error).
struct AvailabilityView: View {
    @State private var viewModel = AvailabilityViewModel()
    @State private var pendingBooking: BookingPair?
    @State private var showingEditor = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: RBSpacing.xl) {
                    RBScreenHeader(title: "Tables")
                    summaryBar
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
        }
        .sheet(isPresented: $showingEditor) {
            SearchEditorSheet(viewModel: viewModel) {
                showingEditor = false
                Task { await viewModel.search() }
            }
            .presentationDetents([.height(380)])
            .presentationBackground(RBColor.surface)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingBooking) { pair in
            BookingConfirmView(
                venue: pair.venue, slot: pair.slot, day: pair.day, partySize: pair.partySize
            ) { pendingBooking = nil }
            .presentationDetents([.medium, .large])
            .presentationBackground(RBColor.surface)
            .presentationDragIndicator(.visible)
        }
        .serverSettingsSheet(isPresented: $showingSettings) {
            Task { await viewModel.search() }
        }
    }

    // MARK: Summary bar

    private var summaryBar: some View {
        Button { showingEditor = true } label: {
            HStack(spacing: 11) {
                Image(systemName: "calendar")
                    .font(.system(size: 18))
                    .foregroundStyle(RBColor.accent)
                Text(viewModel.summaryText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RBColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundStyle(RBColor.textMuted)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .rbCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: State-driven content

    @ViewBuilder
    private var content: some View {
        if !AppConfig.hasAppKey {
            ConnectServerPrompt { showingSettings = true }
                .padding(.top, 40)
        } else {
            searchStates
        }
    }

    @ViewBuilder
    private var searchStates: some View {
        switch viewModel.state {
        case .idle:
            EmptyStateView(
                systemImage: "fork.knife",
                title: "Find a table tonight",
                message: "Checks Resy and OpenTable across every saved spot at once.",
                actionTitle: "Find tables",
                action: { showingEditor = true }
            )
            .padding(.top, 40)

        case .loading:
            VStack(spacing: 11) {
                ForEach(0..<3, id: \.self) { _ in SkeletonVenueCard() }
            }

        case .loaded where viewModel.results.isEmpty:
            EmptyStateView(
                systemImage: "mappin.slash",
                title: "No linked spots yet",
                message: "Link your saved spots to Resy or OpenTable in the Spots tab, then search here."
            )
            .padding(.top, 40)

        case .loaded:
            resultSections

        case .failed where viewModel.isAuthError:
            ConnectServerPrompt { showingSettings = true }
                .padding(.top, 40)

        case .failed where !viewModel.results.isEmpty:
            // A failed *refresh* keeps the last good results visible.
            VStack(alignment: .leading, spacing: 11) {
                failedBanner
                resultSections
            }

        case .failed:
            InlineErrorView(
                title: "Couldn't check tables",
                message: viewModel.errorMessage ?? "Your booking server didn't respond.",
                retry: { Task { await viewModel.search() } }
            )
            .padding(.top, 40)
        }
    }

    private var failedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(RBColor.amber)
            Text("Couldn't refresh — showing your last results.")
                .font(.system(size: 13))
                .foregroundStyle(RBColor.textSecondary)
            Spacer()
            Button("Retry") { Task { await viewModel.search() } }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RBColor.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard(fill: RBColor.amberSoft, bordered: false)
    }

    @ViewBuilder
    private var resultSections: some View {
        if viewModel.availableResults.isEmpty {
            noticeBanner
        }
        if !viewModel.availableResults.isEmpty {
            venueSection("AVAILABLE", viewModel.availableResults, countColor: RBColor.success)
        }
        if !viewModel.unavailableResults.isEmpty {
            venueSection("NO TABLES", viewModel.unavailableResults)
        }
    }

    private func venueSection(
        _ title: String,
        _ venues: [VenueAvailabilityDTO],
        countColor: Color = RBColor.textMuted
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            RBSectionLabel(title: title, count: "\(venues.count) spots", countColor: countColor)
            ForEach(venues) { venueCard($0) }
        }
    }

    private func venueCard(_ venue: VenueAvailabilityDTO) -> some View {
        VenueAvailabilityCard(venue: venue) { slot in
            pendingBooking = BookingPair(
                venue: venue,
                slot: slot,
                day: DateFormatter.dayKey.string(from: viewModel.day),
                partySize: viewModel.partySize
            )
        }
    }

    private var noticeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(RBColor.textSecondary)
            Text("No tables at any of your \(viewModel.results.count) spots for \(viewModel.summaryText). Try another date, time, or party size.")
                .font(.system(size: 13.5))
                .foregroundStyle(RBColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard(fill: RBColor.surface2, bordered: false)
    }
}

// MARK: - Search editor

/// Bottom sheet to set date, time, and party, then run the search. Replaces the
/// inline pickers with one deliberate edit step behind the summary bar.
private struct SearchEditorSheet: View {
    @Bindable var viewModel: AvailabilityViewModel
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.lg) {
            Text("When")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
                .padding(.top, RBSpacing.sm)

            row {
                Text("Date").foregroundStyle(RBColor.textSecondary)
                Spacer()
                DatePicker("", selection: $viewModel.day, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
            }
            row {
                Text("Time").foregroundStyle(RBColor.textSecondary)
                Spacer()
                DatePicker("", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            row {
                Text("Party").foregroundStyle(RBColor.textSecondary)
                Spacer()
                Stepper("\(viewModel.partySize)", value: $viewModel.partySize, in: 1...12)
                    .fixedSize()
            }

            Spacer(minLength: 0)

            Button("Find tables", action: onSearch)
                .buttonStyle(.rbPrimary)
        }
        .font(.system(size: 16, weight: .semibold))
        .padding(20)
        .tint(RBColor.accent)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
            .padding(.vertical, 6)
    }
}

struct BookingPair: Identifiable {
    let venue: VenueAvailabilityDTO
    let slot: SlotDTO
    let day: String
    let partySize: Int
    var id: String { "\(venue.id)-\(slot.configToken ?? slot.time ?? "x")" }
}
