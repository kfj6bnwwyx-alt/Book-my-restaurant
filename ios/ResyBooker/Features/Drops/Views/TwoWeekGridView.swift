import SwiftUI

/// The full release window for a drop: every day's times as chips. Multi-select
/// times and reserve them in one go (POST /drops/{id}/reserve). The reserve
/// action is a nav-bar button so it never collides with the floating tab bar.
struct TwoWeekGridView: View {
    let drop: DropDTO

    @State private var window: DropWindowResponse?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var selected: Set<SelectableSlot> = []
    @State private var reserving = false
    @State private var reserveResult: ReserveResponse?
    private let partySize: Int

    init(drop: DropDTO) {
        self.drop = drop
        self.partySize = drop.autobook.partySize ?? 2
    }

    struct SelectableSlot: Hashable {
        let day: String
        let configToken: String
        let time: String?
    }

    var body: some View {
        ZStack {
            RBColor.bg.ignoresSafeArea()
            content
        }
        .navigationTitle(drop.venueName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(reserving ? "Reserving…" : "Reserve\(selected.isEmpty ? "" : " \(selected.count)")") {
                    Task { await reserve() }
                }
                .tint(RBColor.accent)
                .disabled(selected.isEmpty || reserving)
            }
        }
        .task { await load() }
        .sheet(isPresented: Binding(
            get: { reserveResult != nil },
            set: { if !$0 { reserveResult = nil } }
        )) {
            if let result = reserveResult {
                ReserveResultSheet(result: result) { Task { await load() } }
                    .presentationDetents([.medium])
                    .presentationBackground(RBColor.surface)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView().tint(RBColor.accent)
        } else if let errorMessage {
            InlineErrorView(title: "Couldn't load the window", message: errorMessage) {
                Task { await load() }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: RBSpacing.lg) {
                    Text("Party of \(partySize) · tap times to select")
                        .font(.system(size: 13))
                        .foregroundStyle(RBColor.textSecondary)
                    let days = window?.results ?? []
                    let withTables = days.filter { $0.available && !bookable($0).isEmpty }
                    if withTables.isEmpty {
                        EmptyStateView(
                            systemImage: "calendar",
                            title: "No tables in the window yet",
                            message: "Nothing open across the released days right now. Check back when the next batch drops."
                        )
                        .padding(.top, 32)
                    } else {
                        ForEach(withTables) { day in
                            dayRow(day)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
        }
    }

    private func dayRow(_ day: DropDayDTO) -> some View {
        VStack(alignment: .leading, spacing: RBSpacing.sm) {
            Text(dayHeader(day.day))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
            RBFlowLayout(spacing: RBSpacing.sm) {
                ForEach(Array(bookable(day).enumerated()), id: \.offset) { _, slot in
                    let key = SelectableSlot(day: day.day, configToken: slot.configToken ?? "", time: slot.time)
                    Button {
                        if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
                    } label: {
                        Text(SlotTime.display(slot.time))
                    }
                    .buttonStyle(.rbChip(selected: selected.contains(key)))
                }
            }
        }
        .padding(.bottom, RBSpacing.xs)
    }

    private func bookable(_ day: DropDayDTO) -> [SlotDTO] {
        day.slots.filter { $0.configToken != nil }
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
            window = try await APIClient.shared.dropWindow(drop.id, partySize: partySize)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reserve() async {
        let slots = selected.map { ReserveSlot(configToken: $0.configToken, day: $0.day, time: $0.time) }
        guard !slots.isEmpty else { return }
        reserving = true
        defer { reserving = false }
        do {
            let resp = try await APIClient.shared.reserve(drop.id, ReserveRequest(partySize: partySize, slots: slots))
            selected = []
            reserveResult = resp
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Outcome of a multi-slot reserve: how many booked, with a per-slot list.
struct ReserveResultSheet: View {
    let result: ReserveResponse
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            RBColor.surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: RBSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.booked) of \(result.requested) booked")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(result.booked > 0 ? RBColor.textPrimary : RBColor.textPrimary)
                    Text(result.booked == result.requested
                         ? "All selected times were reserved."
                         : "Some times were taken before we got them.")
                        .font(.system(size: 14))
                        .foregroundStyle(RBColor.textSecondary)
                }
                .padding(.top, RBSpacing.sm)

                ScrollView {
                    VStack(spacing: RBSpacing.sm) {
                        ForEach(result.results) { row in
                            HStack(spacing: RBSpacing.md) {
                                Image(systemName: icon(row.status))
                                    .font(.system(size: 16))
                                    .foregroundStyle(tint(row.status))
                                Text("\(dayLabel(row.day)) · \(row.time)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(RBColor.textPrimary)
                                Spacer()
                                Text(label(row.status))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(tint(row.status))
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .rbCard(fill: RBColor.surface2, bordered: false)
                        }
                    }
                }

                Button("Done") { dismiss(); onClose() }
                    .buttonStyle(.rbPrimary)
            }
            .padding(20)
        }
        .tint(RBColor.accent)
    }

    private func icon(_ status: String) -> String {
        switch status {
        case "booked": "checkmark.circle.fill"
        case "taken": "minus.circle"
        default: "exclamationmark.triangle.fill"
        }
    }
    private func tint(_ status: String) -> Color {
        switch status {
        case "booked": RBColor.success
        case "taken": RBColor.textMuted
        default: RBColor.red
        }
    }
    private func label(_ status: String) -> String {
        switch status {
        case "booked": "Booked"
        case "taken": "Taken"
        default: "Failed"
        }
    }
    private func dayLabel(_ ymd: String) -> String {
        guard let date = DateFormatter.dayKey.date(from: ymd) else { return ymd }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
