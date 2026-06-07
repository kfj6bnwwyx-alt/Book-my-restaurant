import SwiftUI

/// Configure auto-book for a drop (PATCH /drops/{id}). When armed, the server
/// grabs the best matching table the instant the drop opens.
struct AutoBookSetupSheet: View {
    let drop: DropDTO
    var onSaved: (DropDTO) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = false
    @State private var partySize = 2
    @State private var earliest = Self.time(19, 0)
    @State private var latest = Self.time(21, 0)
    @State private var days: Set<Int> = []
    @State private var priority = "prime"
    @State private var notifyOnFail = true
    @State private var saving = false
    @State private var error: String?

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let priorities = [("prime", "Prime times"), ("earliest", "Earliest"), ("latest", "Latest")]

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RBSpacing.lg) {
                        toggleRow
                        if enabled { configFields }
                        if let error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(RBColor.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(saving ? "Saving…" : "Save", action: save)
                            .buttonStyle(.rbPrimary)
                            .disabled(saving)
                            .padding(.top, RBSpacing.xs)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Auto-book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(RBColor.accent)
                }
            }
        }
        .tint(RBColor.accent)
        .onAppear(perform: prefill)
    }

    private var toggleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(drop.venueName).font(.system(size: 15, weight: .semibold)).foregroundStyle(RBColor.textPrimary)
                Text("Grab a table when this drop opens").font(.system(size: 12.5)).foregroundStyle(RBColor.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $enabled).labelsHidden().tint(RBColor.success)
        }
        .padding(14)
        .rbCard(fill: RBColor.surface)
    }

    @ViewBuilder
    private var configFields: some View {
        row("Party") {
            Stepper("\(partySize)", value: $partySize, in: 1...12).fixedSize()
        }
        daysRow
        row("Earliest") {
            DatePicker("", selection: $earliest, displayedComponents: .hourAndMinute).labelsHidden()
        }
        row("Latest") {
            DatePicker("", selection: $latest, displayedComponents: .hourAndMinute).labelsHidden()
        }
        row("Priority") {
            Picker("", selection: $priority) {
                ForEach(priorities, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .tint(RBColor.textPrimary)
        }
        row("Notify if it misses") {
            Toggle("", isOn: $notifyOnFail).labelsHidden().tint(RBColor.success)
        }
    }

    private var daysRow: some View {
        VStack(alignment: .leading, spacing: RBSpacing.sm) {
            Text("Days")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RBColor.textSecondary)
            RBFlowLayout(spacing: RBSpacing.sm) {
                ForEach(0..<7, id: \.self) { i in
                    Button {
                        if days.contains(i) { days.remove(i) } else { days.insert(i) }
                    } label: {
                        Text(weekdays[i])
                    }
                    .buttonStyle(.rbChip(selected: days.contains(i)))
                }
            }
            Text(days.isEmpty ? "Any day" : "Tap to limit which days to book")
                .font(.system(size: 12))
                .foregroundStyle(RBColor.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard(fill: RBColor.surface)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(RBColor.textSecondary)
            Spacer()
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .rbCard(fill: RBColor.surface)
    }

    // MARK: Data

    private func prefill() {
        enabled = drop.autobookEnabled
        partySize = drop.autobook.partySize ?? 2
        earliest = Self.parse(drop.autobook.earliest) ?? Self.time(19, 0)
        latest = Self.parse(drop.autobook.latest) ?? Self.time(21, 0)
        days = Self.parseDays(drop.autobook.days, weekdays: weekdays)
        priority = drop.autobook.priority ?? "prime"
        notifyOnFail = drop.autobook.notifyOnFail ?? true
    }

    private func save() {
        let req = DropUpdateRequest(
            autobookEnabled: enabled,
            abPartySize: partySize,
            abDays: daysString(),
            abEarliest: Self.hm(earliest),
            abLatest: Self.hm(latest),
            abPriority: priority,
            abNotifyOnFail: notifyOnFail
        )
        saving = true
        error = nil
        Task {
            do {
                let updated = try await APIClient.shared.updateDrop(drop.id, req)
                onSaved(updated)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }

    /// Empty string means "any day" (all or none selected).
    private func daysString() -> String {
        if days.isEmpty || days.count == 7 { return "" }
        return days.sorted().map { weekdays[$0] }.joined(separator: ",")
    }

    private static func time(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now
    }
    private static func parse(_ hm: String?) -> Date? {
        guard let hm else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: hm)
    }
    private static func hm(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    private static func parseDays(_ s: String?, weekdays: [String]) -> Set<Int> {
        guard let s, !s.isEmpty else { return [] }
        let names = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return Set(names.compactMap { weekdays.firstIndex(of: $0) })
    }
}
