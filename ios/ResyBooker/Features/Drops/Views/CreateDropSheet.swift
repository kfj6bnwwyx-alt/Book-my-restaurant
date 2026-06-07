import SwiftUI

/// Add a drop: pick a linked Resy spot, set its release cadence/schedule, and
/// POST it. Only Resy is supported (the server rejects other providers).
struct CreateDropSheet: View {
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pins: [PinDTO] = []
    @State private var loadingPins = true
    @State private var selectedPinId: Int?

    @State private var cadence = "biweekly"
    @State private var weekday = 2                 // 0=Mon..6=Sun
    @State private var dayOfMonth = 1
    @State private var anchorDate = Date()
    @State private var releaseTime = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: .now
    ) ?? .now
    @State private var windowDays = 14

    @State private var creating = false
    @State private var error: String?

    private let cadences = ["daily", "weekly", "biweekly", "monthly"]
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var resyPins: [PinDTO] {
        pins.filter { $0.linked && ($0.provider?.lowercased() == "resy") && $0.venueId != nil }
    }
    private var selectedPin: PinDTO? {
        resyPins.first { $0.id == selectedPinId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                content
            }
            .navigationTitle("New drop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(RBColor.accent)
                }
            }
            .task { await loadPins() }
        }
        .tint(RBColor.accent)
    }

    @ViewBuilder
    private var content: some View {
        if loadingPins {
            ProgressView().tint(RBColor.accent)
        } else if resyPins.isEmpty {
            EmptyStateView(
                systemImage: "mappin.slash",
                title: "No linked Resy spots",
                message: "Link a saved spot to a Resy venue in the Spots tab first, then add it as a drop here."
            )
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RBSpacing.lg) {
                row("Venue") {
                    Picker("Venue", selection: $selectedPinId) {
                        ForEach(resyPins) { pin in
                            Text(pin.name).tag(Optional(pin.id))
                        }
                    }
                    .labelsHidden()
                    .tint(RBColor.textPrimary)
                }
                row("Cadence") {
                    Picker("Cadence", selection: $cadence) {
                        ForEach(cadences, id: \.self) { c in
                            Text(cadenceLabel(c)).tag(c)
                        }
                    }
                    .labelsHidden()
                    .tint(RBColor.textPrimary)
                }

                if cadence == "weekly" {
                    row("Release day") {
                        Picker("Day", selection: $weekday) {
                            ForEach(0..<7, id: \.self) { i in Text(weekdays[i]).tag(i) }
                        }
                        .labelsHidden()
                        .tint(RBColor.textPrimary)
                    }
                } else if cadence == "monthly" {
                    row("Day of month") {
                        Stepper("\(dayOfMonth)", value: $dayOfMonth, in: 1...28).fixedSize()
                    }
                } else if cadence == "biweekly" {
                    row("Known release date") {
                        DatePicker("", selection: $anchorDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                row("Release time") {
                    DatePicker("", selection: $releaseTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                row("Window") {
                    Stepper("\(windowDays) days", value: $windowDays, in: 1...30).fixedSize()
                }

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(RBColor.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(creating ? "Adding…" : "Add drop", action: create)
                    .buttonStyle(.rbPrimary)
                    .disabled(selectedPin == nil || creating)
                    .padding(.top, RBSpacing.xs)
            }
            .padding(18)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RBColor.textSecondary)
            Spacer()
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .rbCard(fill: RBColor.surface)
    }

    private func cadenceLabel(_ c: String) -> String {
        switch c {
        case "daily": "Daily"
        case "weekly": "Weekly"
        case "biweekly": "Every 2 weeks"
        case "monthly": "Monthly"
        default: c.capitalized
        }
    }

    private func loadPins() async {
        loadingPins = true
        defer { loadingPins = false }
        pins = (try? await APIClient.shared.fetchPins()) ?? []
        if selectedPinId == nil { selectedPinId = resyPins.first?.id }
    }

    private func create() {
        guard let pin = selectedPin, let venueId = pin.venueId else {
            error = "Pick a Resy spot first."
            return
        }
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        let req = DropCreateRequest(
            provider: "resy",
            venueId: venueId,
            venueName: pin.name,
            cadence: cadence,
            releaseWeekday: cadence == "weekly" ? weekday : nil,
            releaseDom: cadence == "monthly" ? dayOfMonth : nil,
            releaseTime: timeFmt.string(from: releaseTime),
            anchorDate: cadence == "biweekly" ? DateFormatter.dayKey.string(from: anchorDate) : nil,
            windowDays: windowDays,
            timezone: TimeZone.current.identifier,
            watching: true
        )
        creating = true
        error = nil
        Task {
            do {
                _ = try await APIClient.shared.createDrop(req)
                onCreated()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                creating = false
            }
        }
    }
}
