import SwiftUI
import SwiftData

/// Spots tab: your imported Google Maps saved pins, each linkable to a Resy or
/// OpenTable venue. Matches the Pencil Spots screens (list, empty, loading,
/// error) plus the import sheet with success/invalid handling. The app key is
/// entered here (Keychain-backed) so the server stops returning 401.
struct PinsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PinsViewModel?
    @State private var showingSettings = false
    @State private var showingSettingsMenu = false
    @State private var showingAdd = false
    @State private var showingMap = false
    @State private var showToast = false
    @State private var toastText = ""
    @State private var route: PinRoute?
    @State private var pendingDelete: PinDTO?
    @State private var selecting = false
    @State private var selection = Set<Int>()
    @State private var confirmBulkDelete = false

    /// Where a tapped spot goes: linked spots open their availability across
    /// dates; unlinked spots go straight to linking (no availability without a venue).
    enum PinRoute: Hashable, Identifiable {
        case dates(PinDTO), link(PinDTO)
        var id: String {
            switch self {
            case .dates(let p): "dates-\(p.id)"
            case .link(let p): "link-\(p.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, RBSpacing.md)
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $route) { route in
                if let vm = viewModel {
                    switch route {
                    case .dates(let pin):
                        RestaurantDatesView(
                            pinId: pin.id, name: pin.name,
                            provider: pin.provider, venueId: pin.venueId
                        )
                    case .link(let pin):
                        LinkPinView(pin: pin, viewModel: vm)
                    }
                }
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "spot")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { pin in
                Button("Delete spot", role: .destructive) { Task { await viewModel?.deletePin(pin) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes it from your saved spots. You can add it again later.")
            }
            .confirmationDialog(
                "Delete \(selection.count) spots?",
                isPresented: $confirmBulkDelete,
                titleVisibility: .visible
            ) {
                Button("Delete \(selection.count) spots", role: .destructive) { Task { await bulkDelete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes them from your saved spots.")
            }
            .rbToast(isPresented: $showToast, style: .success, text: toastText)
            .sheet(isPresented: $showingSettingsMenu) {
                if let vm = viewModel {
                    SettingsSheet(viewModel: vm) { Task { await viewModel?.load() } }
                }
            }
            .serverSettingsSheet(isPresented: $showingSettings) {
                Task { await viewModel?.load() }
            }
            .sheet(isPresented: $showingAdd) {
                if let vm = viewModel {
                    AddSpotSheet(viewModel: vm) { message in
                        toastText = message
                        showToast = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showingMap) {
                if let vm = viewModel {
                    SpotsMapView(pins: vm.pins, viewModel: vm)
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = PinsViewModel(modelContext: modelContext)
                }
                if AppConfig.hasAppKey { await viewModel?.load() }
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if selecting {
            HStack {
                Button("Cancel") { endSelecting() }
                    .foregroundStyle(RBColor.accent)
                Spacer()
                Text(selection.isEmpty ? "Select spots" : "\(selection.count) selected")
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
                Button("Delete") { confirmBulkDelete = true }
                    .foregroundStyle(selection.isEmpty ? RBColor.textMuted : RBColor.red)
                    .disabled(selection.isEmpty)
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(height: 42)
        } else {
            HStack(alignment: .center) {
                Text("Spots")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(RBColor.textPrimary)
                Spacer()
                if viewModel?.pins.isEmpty == false {
                    iconButton("checklist", label: "Select spots") { selecting = true }
                }
                iconButton("plus", label: "Add a spot") {
                    if AppConfig.hasAppKey { showingAdd = true } else { showingSettings = true }
                }
                iconButton("map", label: "Spots map") { showingMap = true }
                iconButton("gearshape", label: "Settings") { showingSettingsMenu = true }
            }
        }
    }

    private func endSelecting() {
        selecting = false
        selection.removeAll()
    }

    private func toggle(_ id: Int) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func bulkDelete() async {
        guard let vm = viewModel else { return }
        for pin in vm.pins.filter({ selection.contains($0.id) }) {
            await vm.deletePin(pin)
        }
        endSelecting()
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RBColor.accent)
                .frame(width: 42, height: 42)
                .rbCard(radius: RBRadius.small)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let vm = viewModel {
            if !AppConfig.hasAppKey {
                stateScroll { ConnectServerPrompt { showingSettings = true }.padding(.top, 40) }
            } else if vm.isLoading && vm.pins.isEmpty {
                stateScroll {
                    VStack(spacing: 11) { ForEach(0..<5, id: \.self) { _ in skeletonRow } }
                }
            } else if vm.pins.isEmpty, let message = vm.errorMessage {
                stateScroll {
                    InlineErrorView(
                        title: "Couldn't load spots",
                        message: message,
                        retry: { Task { await vm.load() } }
                    )
                    .padding(.top, 40)
                }
            } else if vm.pins.isEmpty {
                stateScroll {
                    EmptyStateView(
                        systemImage: "mappin.and.ellipse",
                        title: "No spots yet",
                        message: "Add a restaurant, or bulk-import a Google saved list from Settings, then link each to Resy or OpenTable.",
                        actionTitle: "Add a spot",
                        action: { showingAdd = true }
                    )
                    .padding(.top, 40)
                }
            } else {
                pinsContent(vm)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    /// Non-list states keep the scroll + horizontal inset the header no longer owns.
    private func stateScroll<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        ScrollView { inner().frame(maxWidth: .infinity).padding(.horizontal, 18) }
    }

    private func pinsContent(_ vm: PinsViewModel) -> some View {
        VStack(alignment: .leading, spacing: RBSpacing.sm) {
            RBSectionLabel(
                title: "SAVED SPOTS",
                count: "\(vm.linkedCount) of \(vm.pins.count) linked",
                countColor: vm.linkedCount == vm.pins.count ? RBColor.success : RBColor.textMuted
            )
            .padding(.horizontal, 18)
            pinList(vm)
        }
    }

    private func pinList(_ vm: PinsViewModel) -> some View {
        // A List (not a ScrollView) so each spot gets native swipe-to-delete /
        // unlink. Tap routes by link state: linked -> dates, unlinked -> link.
        List {
            ForEach(vm.pins) { pin in
                Button {
                    if selecting { toggle(pin.id) }
                    else { route = pin.linked ? .dates(pin) : .link(pin) }
                } label: {
                    HStack(spacing: RBSpacing.md) {
                        if selecting {
                            Image(systemName: selection.contains(pin.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(selection.contains(pin.id) ? RBColor.accent : RBColor.textMuted)
                        }
                        PinRow(pin: pin, showsChevron: !selecting)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !selecting {
                        Button(role: .destructive) { pendingDelete = pin } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if pin.linked {
                            Button { Task { await vm.unlinkPin(pin) } } label: {
                                Label("Unlink", systemImage: "link.badge.minus")
                            }
                            .tint(RBColor.amber)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var skeletonRow: some View {
        HStack(spacing: 13) {
            SkeletonBlock(width: 20, height: 20, cornerRadius: 10)
            SkeletonBlock(width: 160, height: 14)
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .rbCard(radius: RBRadius.small)
    }
}

// MARK: - Pin row

struct PinRow: View {
    let pin: PinDTO
    var showsChevron = true

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: pin.linked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(pin.linked ? RBColor.success : RBColor.textMuted)
            VStack(alignment: .leading, spacing: 3) {
                Text(pin.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RBColor.textPrimary)
                if pin.linked, let provider = pin.provider {
                    Text(provider.providerDisplayName)
                        .font(.system(size: 12))
                        .foregroundStyle(RBColor.textSecondary)
                } else if let address = pin.address {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(RBColor.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: RBSpacing.sm)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RBColor.textMuted)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard(radius: RBRadius.small)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Import sheet

struct ImportSheet: View {
    let viewModel: PinsViewModel
    var onSuccess: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case editing
        case importing
        case done(imported: Int, total: Int)
        case failed(String)
    }

    @State private var text = ""
    @State private var phase: Phase = .editing
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            switch phase {
            case .editing:
                editor
            case .importing:
                resultView(
                    icon: nil, tint: RBColor.accent,
                    title: "Importing…",
                    message: "Sending your places to the server."
                )
            case let .done(imported, total):
                doneView(imported: imported, total: total)
            case let .failed(message):
                resultView(
                    icon: "exclamationmark.triangle.fill", tint: RBColor.red,
                    title: "Import failed", message: message,
                    primary: ("Try again", { phase = .editing })
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(RBColor.accent)
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    // MARK: Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            Text("Import spots")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
                .padding(.top, RBSpacing.sm)
            Text("Paste your Google Takeout export for a Saved list — the CSV (or a GeoJSON file).")
                .font(.system(size: 13.5))
                .foregroundStyle(RBColor.textSecondary)

            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(RBColor.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .fill(RBColor.surface2)
                        .overlay(
                            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                                .stroke(invalid ? RBColor.red : RBColor.border, lineWidth: 1)
                        )
                )

            if invalid {
                Text("That doesn't look like a Takeout export. Paste the whole CSV (or GeoJSON) file.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(RBColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Import", action: runImport)
                .buttonStyle(.rbPrimary)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Result states

    @ViewBuilder
    private func doneView(imported: Int, total: Int) -> some View {
        if total == 0 {
            // Valid JSON but the server found no places to import → wrong file.
            resultView(
                icon: "doc.questionmark", tint: RBColor.amber,
                title: "No places found",
                message: "We couldn't find any saved places in that file. In Google Takeout, export the GeoJSON of your saved list (Saved → your list → Export), then paste the whole file.",
                primary: ("Try again", { phase = .editing })
            )
        } else if imported == 0 {
            resultView(
                icon: "checkmark.circle.fill", tint: RBColor.success,
                title: "Already up to date",
                message: "All \(total) places in that file are already imported.",
                primary: ("Done", finish)
            )
        } else {
            let suffix = imported == 1 ? "place" : "places"
            let detail = total > imported
                ? "\(imported) new of \(total) in the file."
                : "All \(total) places added."
            resultView(
                icon: "checkmark.circle.fill", tint: RBColor.success,
                title: "Imported \(imported) \(suffix)",
                message: detail,
                primary: ("View spots", finish)
            )
        }
    }

    private func resultView(
        icon: String?, tint: Color, title: String, message: String,
        primary: (String, () -> Void)? = nil
    ) -> some View {
        VStack(spacing: RBSpacing.lg) {
            ZStack {
                Circle().fill(RBColor.surface2).frame(width: 84, height: 84)
                if let icon {
                    Image(systemName: icon).font(.system(size: 34)).foregroundStyle(tint)
                } else {
                    ProgressView().tint(tint)
                }
            }
            VStack(spacing: RBSpacing.xs) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(RBColor.textPrimary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)
            if let primary {
                Button(primary.0, action: primary.1)
                    .buttonStyle(.rbPrimary)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RBSpacing.section)
    }

    private func finish() {
        onSuccess()
        dismiss()
    }

    private func runImport() {
        invalid = false
        // Accept a GeoJSON object/array or a Takeout CSV; the server's
        // total_parsed count is the authoritative validation either way.
        let isJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
        let looksCSV = text.contains(",") && text.contains("\n")
        guard isJSON || looksCSV else {
            invalid = true
            return
        }
        phase = .importing
        Task {
            if let resp = await viewModel.importGeoJSON(text) {
                phase = .done(imported: resp.imported, total: resp.totalParsed)
            } else {
                phase = .failed(viewModel.errorMessage ?? "Import failed.")
            }
        }
    }
}

