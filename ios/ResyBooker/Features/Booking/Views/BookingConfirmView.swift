import SwiftUI

struct BookingConfirmView: View {
    let venue: VenueAvailabilityDTO
    let slot: SlotDTO
    let day: String
    let partySize: Int
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: Phase = .ready
    @State private var resultMessage: String?

    enum Phase { case ready, booking, done, failed }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: iconName)
                    .font(.system(size: 52))
                    .foregroundStyle(iconColor)
                VStack(spacing: 6) {
                    Text(venue.name).font(.title2.weight(.semibold))
                    Text(SlotTime.display(slot.time)).font(.title3)
                        .foregroundStyle(.secondary)
                }
                if let msg = resultMessage {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundStyle(state == .failed ? .red : .green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
                actionButton
            }
            .padding()
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss(); onDismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .ready:
            Button {
                Task { await book() }
            } label: {
                Text("Book this table").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(slot.configToken == nil)
        case .booking:
            ProgressView().frame(maxWidth: .infinity)
        case .done:
            Button {
                dismiss(); onDismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .failed:
            Button {
                Task { await book() }
            } label: {
                Text("Try again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func book() async {
        guard let token = slot.configToken, let venueId = venue.venueId else {
            resultMessage = "This slot can't be booked from the app."
            state = .failed
            return
        }
        state = .booking
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
                state = .done
                resultMessage = "Reservation confirmed."
            } else {
                state = .failed
                resultMessage = "Resy didn't confirm. The slot may be gone."
            }
        } catch {
            state = .failed
            resultMessage = error.localizedDescription
        }
    }

    private var iconName: String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "fork.knife.circle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .done: return .green
        case .failed: return .red
        default: return .accentColor
        }
    }
}
