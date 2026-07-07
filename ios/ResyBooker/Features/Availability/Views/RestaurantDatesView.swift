import SwiftUI

/// One restaurant across the next 14 days: the restaurant-first availability view
/// that complements Tables (all-restaurants-on-one-date). You land here to answer
/// "which night can I actually get into this place," then book a night in one tap.
///
/// Reachable two ways: tapping a linked spot in the Spots tab (pushed), and the
/// calendar button on a Tables result (presented as a sheet). It reuses the drop
/// grid's day/chip rhythm so availability reads the same everywhere.
struct RestaurantDatesView: View {
    let pinId: Int
    let name: String
    let provider: String?
    let venueId: String?
    let days: Int

    @State private var window: AvailabilityWindowResponse?
    @State private var loading = true
    @State private var errorTitle = "Couldn't check dates"
    @State private var errorMessage: String?
    @State private var partySize: Int
    @State private var pendingBooking: BookingPair?
    @State private var showingWatch = false
    @State private var watchCreated = false

    init(pinId: Int, name: String, provider: String?, venueId: String?,
         partySize: Int = 2, days: Int = 14) {
        self.pinId = pinId
        self.name = name
        self.provider = provider
        self.venueId = venueId
        self.days = days
        _partySize = State(initialValue: partySize)
    }

    /// Watches are Resy-only; a prefilled target needs the venue link.
    private var watchTarget: WatchTarget? {
        guard provider?.lowercased() == "resy", let venueId else { return nil }
        return WatchTarget(pinId: pinId, venueId: venueId, venueName: name)
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            content
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if watchTarget != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingWatch = true } label: {
                        Image(systemName: "binoculars")
                    }
                    .tint(RBColor.accent)
                    .accessibilityLabel("Watch \(name) for cancellations")
                }
            }
        }
        .sheet(isPresented: $showingWatch) {
            if let watchTarget {
                CreateWatchSheet(target: watchTarget) { watchCreated = true }
                    .presentationDetents([.large])
                    .presentationBackground(RBColor.surface)
                    .presentationDragIndicator(.visible)
            }
        }
        .rbToast(isPresented: $watchCreated, text: "Watching — check the Drops tab")
        .task(id: partySize) { await load() }
        .sheet(item: $pendingBooking) { pair in
            BookingConfirmView(
                venue: pair.venue, slot: pair.slot, day: pair.day, partySize: pair.partySize
            ) {
                pendingBooking = nil
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(RBColor.surface)
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && window == nil {
            VStack(spacing: 11) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(width: nil, height: 64, cornerRadius: RBRadius.small)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        } else if let errorMessage, window == nil {
            InlineErrorView(
                title: errorTitle,
                message: errorMessage,
                retry: { Task { await load() } }
            )
            .padding(.top, 40)
            .padding(.horizontal, 18)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: RBSpacing.lg) {
                    partyRow
                    let allDays = window?.results ?? []
                    let withTables = allDays.filter { $0.available && !$0.slots.isEmpty }
                    if loading {
                        ProgressView().tint(RBColor.accent).frame(maxWidth: .infinity).padding(.top, 8)
                    }
                    if withTables.isEmpty && !loading {
                        EmptyStateView(
                            systemImage: "calendar",
                            title: "No tables in the next \(days) days",
                            message: watchTarget == nil
                                ? "Nothing open for a party of \(partySize) at \(name) right now. Try a different party size, or check back later."
                                : "Nothing open for a party of \(partySize) at \(name) right now. Watch a night and we'll re-check every minute for a cancellation.",
                            actionTitle: watchTarget == nil ? nil : "Watch for a table",
                            action: watchTarget == nil ? nil : { showingWatch = true }
                        )
                        .padding(.top, 32)
                    } else {
                        ForEach(withTables) { day in dayRow(day) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }

    private var partyRow: some View {
        HStack {
            Text("Party of \(partySize)")
                .foregroundStyle(RBColor.textSecondary)
            Spacer()
            Stepper("", value: $partySize, in: 1...12)
                .labelsHidden()
                .fixedSize()
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .rbCard(fill: RBColor.surface2, bordered: false)
        .tint(RBColor.accent)
    }

    private func dayRow(_ day: DropDayDTO) -> some View {
        VStack(alignment: .leading, spacing: RBSpacing.sm) {
            Text(dayHeader(day.day))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
            RBFlowLayout(spacing: RBSpacing.sm) {
                ForEach(Array(day.slots.enumerated()), id: \.offset) { _, slot in
                    Button { startBooking(slot, day: day.day) } label: {
                        Text(SlotTime.display(slot.time))
                    }
                    .buttonStyle(.rbChip(selected: false))
                    .disabled(slot.configToken == nil)
                    .opacity(slot.configToken == nil ? 0.5 : 1)
                    .accessibilityLabel("Book \(name) on \(dayHeader(day.day)) at \(SlotTime.display(slot.time))")
                }
            }
        }
    }

    private func startBooking(_ slot: SlotDTO, day: String) {
        let venue = VenueAvailabilityDTO(
            pinId: pinId, name: name, provider: provider, venueId: venueId,
            slots: [slot], available: true, error: nil
        )
        pendingBooking = BookingPair(venue: venue, slot: slot, day: day, partySize: partySize)
    }

    private func dayHeader(_ ymd: String) -> String {
        guard let date = DateFormatter.dayKey.date(from: ymd) else { return ymd }
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            window = try await APIClient.shared.availabilityWindow(
                pinId: pinId, partySize: partySize, days: days
            )
        } catch let error as APIError where error.isMissingEndpoint {
            // The per-restaurant dates view calls /availability/window, an
            // endpoint added after the first server build. A 404 here almost
            // always means the booking server is running old code.
            errorTitle = "Your booking server is out of date"
            errorMessage = "This “View dates” screen needs a newer version of your "
                + "ResyBooker server. The Tables tab still works because it uses an "
                + "older endpoint.\n\nTo fix it: rebuild the ResyBooker add-on in "
                + "Home Assistant (Settings → Add-ons → ResyBooker → Rebuild), then "
                + "restart it and try again."
        } catch {
            errorTitle = "Couldn't check dates"
            errorMessage = error.localizedDescription
        }
    }
}
