import SwiftUI

/// A venue a watch can target, resolved before the sheet opens (from a Tables
/// result or the dates view) so the venue picker can be skipped.
struct WatchTarget {
    let pinId: Int?
    let venueId: String
    let venueName: String
    var day: Date? = nil
}

/// Start watching a venue + date: pick a linked Resy spot (or arrive prefilled
/// from a sold-out night), choose the night, party, and time window, and POST.
/// Resy only — the server rejects other providers.
struct CreateWatchSheet: View {
    var target: WatchTarget?
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pins: [PinDTO] = []
    @State private var loadingPins = true
    @State private var selectedPinId: Int?

    @State private var day: Date
    @State private var partySize = 2
    @State private var earliest = WatchFormFields.time("17:00")
    @State private var latest = WatchFormFields.time("22:00")
    @State private var autobook = false
    @State private var notify = true
    @State private var interval = 60

    @State private var creating = false
    @State private var error: String?

    init(target: WatchTarget? = nil, onCreated: @escaping () -> Void) {
        self.target = target
        self.onCreated = onCreated
        _day = State(initialValue: target?.day
            ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
    }

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
            .navigationTitle("New watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(RBColor.accent)
                }
            }
            .task { if target == nil { await loadPins() } }
        }
        .tint(RBColor.accent)
    }

    @ViewBuilder
    private var content: some View {
        if target == nil && loadingPins {
            ProgressView().tint(RBColor.accent)
        } else if target == nil && resyPins.isEmpty {
            EmptyStateView(
                systemImage: "mappin.slash",
                title: "No linked Resy spots",
                message: "Link a saved spot to a Resy venue in the Spots tab first, then watch it for cancellations here."
            )
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RBSpacing.lg) {
                if let target {
                    WatchFormFields.row("Venue") {
                        Text(target.venueName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(RBColor.textPrimary)
                    }
                } else {
                    WatchFormFields.row("Venue") {
                        Picker("Venue", selection: $selectedPinId) {
                            ForEach(resyPins) { pin in
                                Text(pin.name).tag(Optional(pin.id))
                            }
                        }
                        .labelsHidden()
                        .tint(RBColor.textPrimary)
                    }
                }

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

                Button(creating ? "Starting…" : "Start watching", action: create)
                    .buttonStyle(.rbPrimary)
                    .disabled((target == nil && selectedPin == nil) || creating)
                    .padding(.top, RBSpacing.xs)
            }
            .padding(18)
        }
    }

    private func loadPins() async {
        loadingPins = true
        defer { loadingPins = false }
        pins = (try? await APIClient.shared.fetchPins()) ?? []
        if selectedPinId == nil { selectedPinId = resyPins.first?.id }
    }

    private func create() {
        let pinId: Int?
        let venueId: String
        let venueName: String
        if let target {
            (pinId, venueId, venueName) = (target.pinId, target.venueId, target.venueName)
        } else if let pin = selectedPin, let vid = pin.venueId {
            (pinId, venueId, venueName) = (pin.id, vid, pin.name)
        } else {
            error = "Pick a Resy spot first."
            return
        }

        let req = WatchCreateRequest(
            pinId: pinId,
            provider: "resy",
            venueId: venueId,
            venueName: venueName,
            day: DateFormatter.dayKey.string(from: day),
            partySize: partySize,
            earliest: WatchFormFields.hhmm(earliest),
            latest: WatchFormFields.hhmm(latest),
            autobook: autobook,
            notify: notify,
            intervalSeconds: interval,
            timezone: TimeZone.current.identifier
        )
        creating = true
        error = nil
        Task {
            do {
                _ = try await APIClient.shared.createWatch(req)
                onCreated()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                creating = false
            }
        }
    }
}

// MARK: - Shared form fields

/// The watch fields shared by create and edit: night, party, time window,
/// poll interval, and the on-hit behavior (notify vs auto-book).
struct WatchFormFields: View {
    @Binding var day: Date
    @Binding var partySize: Int
    @Binding var earliest: Date
    @Binding var latest: Date
    @Binding var autobook: Bool
    @Binding var notify: Bool
    @Binding var interval: Int

    private static let intervals: [(String, Int)] = [
        ("Every 30s", 30), ("Every minute", 60), ("Every 2 min", 120), ("Every 5 min", 300),
    ]

    var body: some View {
        Group {
            Self.row("Night") {
                DatePicker("", selection: $day, in: Date.now..., displayedComponents: .date)
                    .labelsHidden()
            }
            Self.row("Party") {
                Stepper("\(partySize)", value: $partySize, in: 1...12).fixedSize()
            }
            Self.row("No earlier than") {
                DatePicker("", selection: $earliest, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Self.row("No later than") {
                DatePicker("", selection: $latest, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Self.row("Checks") {
                Picker("Checks", selection: $interval) {
                    ForEach(Self.intervals, id: \.1) { label, seconds in
                        Text(label).tag(seconds)
                    }
                }
                .labelsHidden()
                .tint(RBColor.textPrimary)
            }
            Self.row("Auto-book a match") {
                Toggle("", isOn: $autobook).labelsHidden().tint(RBColor.success)
            }
            if autobook {
                Text("Books the earliest matching table the moment it appears — this charges your Resy card if the venue takes a deposit.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(RBColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            Self.row("Notify me") {
                Toggle("", isOn: $notify).labelsHidden().tint(RBColor.success)
            }
        }
    }

    static func row<Content: View>(
        _ label: String, @ViewBuilder _ content: () -> Content
    ) -> some View {
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

    /// "17:00" -> a Date today at that time (for the pickers).
    static func time(_ hhmm: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let parsed = f.date(from: hhmm) else { return .now }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        return Calendar.current.date(
            bySettingHour: comps.hour ?? 19, minute: comps.minute ?? 0, second: 0, of: .now
        ) ?? .now
    }

    /// Date -> "17:00" for the wire format.
    static func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
