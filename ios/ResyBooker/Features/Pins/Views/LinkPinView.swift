import SwiftUI

struct LinkPinView: View {
    let pin: PinDTO
    let viewModel: PinsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var provider = "resy"
    @State private var candidates: [VenueCandidateDTO] = []
    @State private var isLoading = false
    @State private var linkingId: String?

    var body: some View {
        List {
            Section {
                Picker("Provider", selection: $provider) {
                    Text("Resy").tag("resy")
                    Text("OpenTable").tag("opentable")
                }
                .pickerStyle(.segmented)
                .onChange(of: provider) { _, _ in Task { await loadCandidates() } }
            } header: {
                Text(pin.name)
            } footer: {
                if pin.linked, let v = pin.venueId {
                    Text("Currently linked to \(pin.provider?.capitalized ?? "?") (\(v)).")
                }
            }

            if isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if candidates.isEmpty {
                Section {
                    Text("No candidates found. Try the other provider.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Best matches") {
                    ForEach(candidates) { cand in
                        Button {
                            Task { await link(cand) }
                        } label: {
                            CandidateRow(
                                candidate: cand,
                                isLinking: linkingId == cand.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Link Venue")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCandidates() }
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name ?? "Unknown").font(.body)
                if let loc = candidate.locality {
                    Text(loc).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isLinking {
                ProgressView()
            } else {
                Text(scoreLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scoreColor)
            }
        }
    }

    private var scoreLabel: String { "\(Int(candidate.score))" }

    private var scoreColor: Color {
        switch candidate.score {
        case 90...: return .green
        case 75..<90: return .orange
        default: return .secondary
        }
    }
}
