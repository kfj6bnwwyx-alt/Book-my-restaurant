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
    @State private var errorMessage: String?
    @State private var partySize: Int
    @State private var pendingBooking: BookingPair?

    init(pinId: Int, name: String, provider: String?, venueId: String?,
         partySize: Int = 2, days: Int = 14) {
        self.pinId = pinId
        self.name = name
        self.provider = provider
        self.venueId = venueId
        self.days = days
        _partySize = State(initialValue: partySize)
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            content
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
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
                title: "Couldn't check dates",
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
                            message: "Nothing open for a party of \(partySize) at \(name) right now. Try a different party size, or check back later."
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
