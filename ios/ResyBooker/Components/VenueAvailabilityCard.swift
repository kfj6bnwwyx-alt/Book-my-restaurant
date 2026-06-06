import SwiftUI

struct VenueAvailabilityCard: View {
    let venue: VenueAvailabilityDTO
    let onPickSlot: (SlotDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name).font(.headline)
                    if let p = venue.provider {
                        Text(p.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if venue.available {
                    Text("\(venue.slots.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if venue.available {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bookableSlots, id: \.self) { slot in
                            Button { onPickSlot(slot) } label: {
                                Text(SlotTime.display(slot.time))
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.tint.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(slot.configToken == nil)
                            .opacity(slot.configToken == nil ? 0.5 : 1)
                            .accessibilityLabel(
                                "Book \(venue.name) at \(SlotTime.display(slot.time))"
                            )
                        }
                    }
                }
            } else if let err = venue.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("No tables")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // Only Resy slots carry a config_token, so only they are bookable in-app.
    private var bookableSlots: [SlotDTO] { venue.slots }
}
