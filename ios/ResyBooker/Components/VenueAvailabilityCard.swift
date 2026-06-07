import SwiftUI

/// One venue's availability, matching the Pencil Tables cards. Available venues
/// show a green "N open" badge and tappable time chips; unavailable ones recede
/// (smaller, muted) with a neutral dash, and lookup failures use an amber
/// triangle plus an amber message. Color never does two jobs: green = available,
/// amber = caution, orange is reserved for the user's action (the time chips).
struct VenueAvailabilityCard: View {
    let venue: VenueAvailabilityDTO
    let onPickSlot: (SlotDTO) -> Void

    var body: some View {
        if venue.available {
            availableCard
        } else {
            unavailableCard
        }
    }

    // MARK: Available

    private var availableCard: some View {
        VStack(alignment: .leading, spacing: RBSpacing.lg) {
            HStack(alignment: .center, spacing: RBSpacing.sm) {
                nameBlock(nameSize: 17, nameWeight: .bold,
                          nameColor: RBColor.textPrimary, providerColor: RBColor.textSecondary)
                Spacer(minLength: RBSpacing.sm)
                openBadge
            }
            RBFlowLayout(spacing: RBSpacing.sm) {
                // Index-based ids: two slots can be value-equal (same time/token),
                // which would collide under id: \.self and drop a chip.
                ForEach(Array(venue.slots.enumerated()), id: \.offset) { _, slot in
                    Button { onPickSlot(slot) } label: {
                        Text(SlotTime.display(slot.time))
                    }
                    .buttonStyle(.rbChip(selected: false))
                    .disabled(slot.configToken == nil)
                    .opacity(slot.configToken == nil ? 0.5 : 1)
                    .accessibilityLabel("Book \(venue.name) at \(SlotTime.display(slot.time))")
                }
            }
        }
        .padding(RBSpacing.lg)
        .rbCard()
    }

    private var openBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
            Text("\(venue.slots.count) open").font(.system(size: 12.5, weight: .bold))
        }
        .foregroundStyle(RBColor.success)
        .padding(.vertical, 5)
        .padding(.horizontal, 11)
        .background(RBColor.successSoft, in: Capsule())
    }

    // MARK: Unavailable / error

    private var unavailableCard: some View {
        let isError = (venue.error != nil)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: RBSpacing.sm) {
                nameBlock(nameSize: 16, nameWeight: .semibold,
                          nameColor: RBColor.textSecondary, providerColor: RBColor.textMuted)
                Spacer(minLength: RBSpacing.sm)
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "minus")
                    .font(.system(size: 14))
                    .foregroundStyle(isError ? RBColor.amber : RBColor.textMuted)
            }
            Text(venue.error ?? "No tables for this date and party.")
                .font(.system(size: 12.5))
                .foregroundStyle(isError ? RBColor.amber : RBColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RBSpacing.lg)
        .rbCard()
        .opacity(0.85)
    }

    // MARK: Pieces

    private func nameBlock(nameSize: CGFloat, nameWeight: Font.Weight,
                           nameColor: Color, providerColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(venue.name)
                .font(.system(size: nameSize, weight: nameWeight))
                .foregroundStyle(nameColor)
                .fixedSize(horizontal: false, vertical: true)
            if let p = venue.provider {
                Text(p.providerDisplayName)
                    .font(.system(size: 12))
                    .foregroundStyle(providerColor)
            }
        }
    }

}
