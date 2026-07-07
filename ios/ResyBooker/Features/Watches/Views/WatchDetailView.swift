import SwiftUI

/// One watch: status, target night, poll cadence, and the controls — check now,
/// pause/resume, edit, delete. Mirrors the drop countdown detail's layout.
struct WatchDetailView: View {
    @State private var watch: WatchDTO
    let viewModel: WatchesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var busy = false
    @State private var checkResult: String?
    @State private var errorMessage: String?

    init(watch: WatchDTO, viewModel: WatchesViewModel) {
        _watch = State(initialValue: watch)
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: RBSpacing.lg) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(watch.venueName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(RBColor.textPrimary)
                        WatchStatusBadge(watch: watch)
                    }

                    statusCard
                    infoCard
                    actions

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(RBColor.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) {
            EditWatchSheet(watch: watch) { updated in
                watch = updated
                viewModel.replace(updated)
            }
            .presentationDetents([.large])
            .presentationBackground(RBColor.surface)
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Remove this watch?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Remove watch", role: .destructive) {
                Task {
                    await viewModel.delete(watch)
                    dismiss()
                }
            }
        } message: {
            Text("Stops checking \(watch.venueName) for \(watch.dayDisplay).")
        }
    }

    // MARK: - Cards

    /// What the watch has seen: found times, booked confirmation, error detail,
    /// or a quiet "still looking" line. Always shows the last-checked stamp.
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: RBSpacing.sm) {
            Text(statusHeadline)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = statusDetail {
                Text(detail)
                    .font(.system(size: 13.5))
                    .foregroundStyle(watch.presentation == .error ? RBColor.red : RBColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let checked = watch.lastCheckedDisplay {
                Text(checked)
                    .font(.system(size: 12.5))
                    .foregroundStyle(RBColor.textMuted)
            }
        }
        .padding(RBSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard()
    }

    private var statusHeadline: String {
        if let checkResult { return checkResult }
        switch watch.presentation {
        case .watching:
            return watch.autobook
                ? "Watching — will book the first match automatically."
                : "Watching — you'll hear the second a table frees up."
        case .paused: return "Paused. Resume to keep checking."
        case .found: return "Tables appeared in your window!"
        case .booked: return "Booked 🎉"
        case .expired: return "The night has passed."
        case .error: return "The last check failed."
        }
    }

    private var statusDetail: String? {
        guard let detail = watch.foundDetail, !detail.isEmpty else { return nil }
        switch watch.presentation {
        case .found: return "Times seen: \(detail). Book fast — cancellations go quickly."
        case .booked: return "Confirmed \(detail)."
        default: return detail
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow("Night", watch.dayDisplay)
            divider
            infoRow("Party", "\(watch.partySize)")
            divider
            infoRow("Time window", watch.windowDisplay)
            divider
            infoRow("Checks", watch.intervalDisplay)
            divider
            infoRow("On a hit", watch.autobook ? "Auto-book" : "Notify only")
        }
        .padding(.horizontal, RBSpacing.lg)
        .rbCard()
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: RBSpacing.md) {
            if watch.active {
                Button(busy ? "Checking…" : "Check now") { checkNow() }
                    .buttonStyle(.rbPrimary)
                    .disabled(busy)
            } else if watch.presentation != .booked {
                Button(busy ? "Resuming…" : "Resume watching") { setActive(true) }
                    .buttonStyle(.rbPrimary)
                    .disabled(busy)
            }
            HStack(spacing: RBSpacing.md) {
                if watch.active {
                    Button("Pause") { setActive(false) }
                        .buttonStyle(.rbSecondary)
                        .disabled(busy)
                }
                Button("Edit") { showingEdit = true }
                    .buttonStyle(.rbSecondary)
                    .disabled(busy)
                Button("Remove") { confirmingDelete = true }
                    .buttonStyle(.rbSecondary)
                    .tint(RBColor.red)
                    .disabled(busy)
            }
        }
    }

    private func checkNow() {
        busy = true
        errorMessage = nil
        checkResult = nil
        Task {
            defer { busy = false }
            do {
                let result = try await APIClient.shared.checkWatch(watch.id)
                switch result.status {
                case "watching":
                    checkResult = "Checked just now — nothing open in your window yet."
                case "found":
                    let times = (result.times ?? []).joined(separator: ", ")
                    checkResult = times.isEmpty ? "Tables found!" : "Tables found: \(times)"
                case "booked":
                    checkResult = "Booked\(result.time.map { " for \($0)" } ?? "") 🎉"
                case "expired":
                    checkResult = "This night has already passed."
                default:
                    checkResult = nil
                    errorMessage = result.error ?? "The check failed."
                }
                // The check mutates the watch server-side; re-fetch so status,
                // found_detail, and last_checked reflect it.
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setActive(_ active: Bool) {
        busy = true
        errorMessage = nil
        checkResult = nil
        Task {
            defer { busy = false }
            do {
                let updated = try await APIClient.shared.updateWatch(
                    watch.id, WatchUpdateRequest(active: active)
                )
                watch = updated
                viewModel.replace(updated)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refresh() async {
        if let all = try? await APIClient.shared.fetchWatches(),
           let fresh = all.first(where: { $0.id == watch.id }) {
            watch = fresh
            viewModel.replace(fresh)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(RBColor.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RBColor.textPrimary)
        }
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(RBColor.border).frame(height: 1)
    }
}

// MARK: - Edit sheet

/// Adjust an existing watch (PATCH). Same fields as create, minus the venue.
struct EditWatchSheet: View {
    let watch: WatchDTO
    var onSaved: (WatchDTO) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var partySize: Int
    @State private var earliest: Date
    @State private var latest: Date
    @State private var autobook: Bool
    @State private var notify: Bool
    @State private var interval: Int
    @State private var saving = false
    @State private var error: String?

    init(watch: WatchDTO, onSaved: @escaping (WatchDTO) -> Void) {
        self.watch = watch
        self.onSaved = onSaved
        _day = State(initialValue: DateFormatter.dayKey.date(from: watch.day) ?? .now)
        _partySize = State(initialValue: watch.partySize)
        _earliest = State(initialValue: WatchFormFields.time(watch.earliest))
        _latest = State(initialValue: WatchFormFields.time(watch.latest))
        _autobook = State(initialValue: watch.autobook)
        _notify = State(initialValue: watch.notify)
        _interval = State(initialValue: watch.intervalSeconds)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RBSpacing.lg) {
                        WatchFormFields(
                            day: $day, partySize: $partySize,
                            earliest: $earliest, latest: $latest,
                            autobook: $autobook, notify: $notify, interval: $interval
                        )

                        if let error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(RBColor.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button(saving ? "Saving…" : "Save changes", action: save)
                            .buttonStyle(.rbPrimary)
                            .disabled(saving)
                            .padding(.top, RBSpacing.xs)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Edit watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(RBColor.accent)
                }
            }
        }
        .tint(RBColor.accent)
    }

    private func save() {
        saving = true
        error = nil
        let req = WatchUpdateRequest(
            day: DateFormatter.dayKey.string(from: day),
            partySize: partySize,
            earliest: WatchFormFields.hhmm(earliest),
            latest: WatchFormFields.hhmm(latest),
            autobook: autobook,
            notify: notify,
            intervalSeconds: interval
        )
        Task {
            do {
                let updated = try await APIClient.shared.updateWatch(watch.id, req)
                onSaved(updated)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}
