import SwiftUI

/// Link a saved pin to a Resy or OpenTable venue. Matches the Pencil Link Venue
/// screen: provider toggle, ranked candidate cards with a match-score badge.
struct LinkPinView: View {
    let pin: PinDTO
    let viewModel: PinsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var provider = "resy"
    @State private var candidates: [VenueCandidateDTO] = []
    @State private var isLoading = false
    @State private var linkingId: String?

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: RBSpacing.lg) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(pin.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(RBColor.textPrimary)
                        if pin.linked, let v = pin.venueId, let p = pin.provider {
                            Text("Linked to \(p.providerDisplayName) (\(v))")
                                .font(.system(size: 13))
                                .foregroundStyle(RBColor.success)
                        } else {
                            Text("Pick the matching venue")
                                .font(.system(size: 14))
                                .foregroundStyle(RBColor.textSecondary)
                        }
                    }

                    providerToggle
                    candidateStates
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCandidates() }
    }

    private var providerToggle: some View {
        HStack(spacing: 0) {
            ForEach(["resy", "opentable"], id: \.self) { p in
                Button {
                    guard provider != p else { return }
                    provider = p
                    Task { await loadCandidates() }
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
    }

    @ViewBuilder
    private var candidateStates: some View {
        if isLoading {
            VStack(spacing: 11) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(width: nil, height: 64, cornerRadius: RBRadius.small)
                }
            }
        } else if candidates.isEmpty {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No matches found",
                message: "No \(provider.providerDisplayName) candidates near this pin. Try the other provider."
            )
            .padding(.top, 32)
        } else {
            VStack(alignment: .leading, spacing: 11) {
                RBSectionLabel(title: "BEST MATCHES", count: "\(candidates.count)")
                ForEach(candidates) { cand in
                    Button { Task { await link(cand) } } label: {
                        CandidateRow(candidate: cand, isLinking: linkingId == cand.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(linkingId != nil)
                }
            }
        }
    }

    private func loadCandidates() async {
        isLoading = true
        defer { isLoading = false }
        candidates = await viewModel.candidates(for: pin, provider: provider)
    }

    private func link(_ cand: VenueCandidateDTO) async {
        linkingId = cand.id
        await viewModel.link(pin: pin, to: cand, provider: provider)
        linkingId = nil
        dismiss()
    }
}

struct CandidateRow: View {
    let candidate: VenueCandidateDTO
    let isLinking: Bool

    var body: some View {
        HStack(spacing: RBSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name ?? "Unknown")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RBColor.textPrimary)
                if let loc = candidate.locality {
                    Text(loc)
                        .font(.system(size: 12))
                        .foregroundStyle(RBColor.textSecondary)
                }
            }
            Spacer(minLength: RBSpacing.sm)
            if isLinking {
                ProgressView().tint(RBColor.accent)
            } else {
                scoreBadge
            }
        }
        .padding(RBSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                .fill(RBColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .stroke(RBColor.border, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    private var scoreBadge: some View {
        Text("\(Int(candidate.score))")
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(scoreTint)
            .padding(.vertical, 5)
            .padding(.horizontal, 11)
            .background(scoreSoft, in: Capsule())
    }

    // >=90 is almost always correct (green); 75-89 needs a glance (amber); lower is a long shot.
    private var scoreTint: Color {
        switch candidate.score {
        case 90...: RBColor.success
        case 75..<90: RBColor.amber
        default: RBColor.textMuted
        }
    }
    private var scoreSoft: Color {
        switch candidate.score {
        case 90...: RBColor.successSoft
        case 75..<90: RBColor.amberSoft
        default: RBColor.surface2
        }
    }
}
