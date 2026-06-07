import SwiftUI

/// One-tap booking, as a single sheet that moves through its states: confirm →
/// securing → confirmed / failed. Matches the Pencil Booking screens. Green is
/// the confirmation signal (check only, neutral circle); orange is the action.
struct BookingConfirmView: View {
    let venue: VenueAvailabilityDTO
    let slot: SlotDTO
    let day: String
    let partySize: Int
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .ready
    @State private var resultMessage: String?
    @State private var confirmation: String?

    enum Phase { case ready, booking, done, failed }

    var body: some View {
        ZStack {
            RBColor.surface.ignoresSafeArea()
            VStack(spacing: RBSpacing.lg) {
                switch phase {
                case .ready: readyView
                case .booking: bookingView
                case .done: doneView
                case .failed: failedView
                }
            }
            .padding(20)
        }
        .tint(RBColor.accent)
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    // MARK: States

    private var readyView: some View {
        VStack(spacing: RBSpacing.lg) {
            Spacer(minLength: 0)
            VStack(spacing: RBSpacing.sm) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(RBColor.accent)
                Text(venue.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(whenText)
                    .font(.system(size: 15))
                    .foregroundStyle(RBColor.textSecondary)
            }
            detailsCard
            Spacer(minLength: 0)
            if slot.configToken == nil {
                Text("This time is view-only (OpenTable). Book it in the OpenTable app.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(RBColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: RBSpacing.md) {
                Button("Book this table") { Task { await book() } }
                    .buttonStyle(.rbPrimary)
                    .disabled(slot.configToken == nil)
                Button("Not now") { close() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RBColor.textSecondary)
            }
        }
    }

    private var bookingView: some View {
        VStack(spacing: RBSpacing.md) {
            Spacer()
            ProgressView().controlSize(.large).tint(RBColor.accent)
            Text("Securing your table…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RBColor.textPrimary)
            Text("\(venue.name) · \(SlotTime.display(slot.time))")
                .font(.system(size: 14))
                .foregroundStyle(RBColor.textSecondary)
            Spacer()
        }
    }

    private var doneView: some View {
        VStack(spacing: RBSpacing.lg) {
            Spacer()
            ZStack {
                Circle().fill(RBColor.surface2).frame(width: 84, height: 84)
                Image(systemName: "checkmark").font(.system(size: 38, weight: .semibold)).foregroundStyle(RBColor.success)
            }
            VStack(spacing: RBSpacing.xs) {
                Text("RESERVATION CONFIRMED")
                    .font(.system(size: 13, weight: .bold)).tracking(0.8)
                    .foregroundStyle(RBColor.success)
                Text(venue.name).font(.system(size: 22, weight: .bold)).foregroundStyle(RBColor.textPrimary)
                Text(whenText).font(.system(size: 15)).foregroundStyle(RBColor.textSecondary)
            }
            detailsCard
            Spacer()
            Button("Done") { close() }.buttonStyle(.rbPrimary)
        }
    }

    private var failedView: some View {
        VStack(spacing: RBSpacing.lg) {
            Spacer()
            ZStack {
                Circle().fill(RBColor.redSoft).frame(width: 84, height: 84)
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(RBColor.red)
            }
            VStack(spacing: RBSpacing.xs) {
                Text("Booking failed").font(.system(size: 18, weight: .semibold)).foregroundStyle(RBColor.textPrimary)
                Text(resultMessage ?? "Couldn't confirm the reservation.")
                    .font(.system(size: 14)).foregroundStyle(RBColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)
            Spacer()
            VStack(spacing: RBSpacing.md) {
                Button("Try again") { Task { await book() } }.buttonStyle(.rbPrimary)
                Button("Close") { close() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RBColor.textSecondary)
            }
        }
    }

    // MARK: Pieces

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow("Party", "\(partySize) \(partySize == 1 ? "guest" : "guests")")
            divider
            detailRow("Provider", (venue.provider ?? "resy").providerDisplayName)
            if let confirmation {
                divider
                detailRow("Confirmation", confirmation)
            }
        }
        .padding(.horizontal, RBSpacing.lg)
        .rbCard(fill: RBColor.surface2, bordered: false)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(RBColor.textSecondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(RBColor.textPrimary)
        }
        .font(.system(size: 14))
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(RBColor.border).frame(height: 1)
    }

    private var whenText: String {
        let dayText: String
        if let d = DateFormatter.dayKey.date(from: day) {
            dayText = DateFormatter.summaryDay.string(from: d)
        } else {
            dayText = day
        }
        return "\(dayText)  ·  \(SlotTime.display(slot.time))"
    }

    private func close() { dismiss(); onDismiss() }

    private func book() async {
        guard let token = slot.configToken, let venueId = venue.venueId else {
            resultMessage = "This time can't be booked from the app."
            phase = .failed
            return
        }
        phase = .booking
        let req = BookRequest(
            pinId: venue.pinId,
            venueId: venueId,
            venueName: venue.name,
            day: day,
            partySize: partySize,
            configToken: token
        )
        do {
            let resp = try await APIClient.shared.book(req)
            if resp.ok {
                if let id = resp.reservationId { confirmation = "RES-\(id)" }
                phase = .done
            } else {
                resultMessage = "Resy didn't confirm. The table may be gone — try another time."
                phase = .failed
            }
        } catch {
            resultMessage = error.localizedDescription
            phase = .failed
        }
    }
}
