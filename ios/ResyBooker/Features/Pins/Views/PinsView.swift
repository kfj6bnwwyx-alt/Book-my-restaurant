import SwiftUI
import SwiftData

/// Spots tab: your imported Google Maps saved pins, each linkable to a Resy or
/// OpenTable venue. Matches the Pencil Spots screens (list, empty, loading,
/// error) plus the import sheet with success/invalid handling. The app key is
/// entered here (Keychain-backed) so the server stops returning 401.
struct PinsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PinsViewModel?
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var showToast = false
    @State private var toastText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RBSpacing.lg) {
                        header
                        content
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .rbToast(isPresented: $showToast, style: .success, text: toastText)
            .sheet(isPresented: $showingImporter) {
                if let vm = viewModel {
                    ImportSheet(viewModel: vm) {
                        toastText = vm.importSummary ?? "Spots imported"
                        showToast = true
                    }
                    .presentationDetents([.large])
                    .presentationBackground(RBColor.surface)
                    .presentationDragIndicator(.visible)
                }
            }
            .serverSettingsSheet(isPresented: $showingSettings) {
                Task { await viewModel?.load() }
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

    private var header: some View {
        HStack(alignment: .center) {
            Text("Spots")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
            Spacer()
            iconButton("gearshape", label: "Server settings") { showingSettings = true }
            iconButton("square.and.arrow.down", label: "Import spots") {
                // No key means every import 401s; send them to set it up first.
                if AppConfig.hasAppKey { showingImporter = true } else { showingSettings = true }
            }
        }
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
                ConnectServerPrompt { showingSettings = true }
                    .padding(.top, 40)
            } else if vm.isLoading && vm.pins.isEmpty {
                VStack(spacing: 11) {
                    ForEach(0..<5, id: \.self) { _ in skeletonRow }
                }
            } else if vm.pins.isEmpty, let message = vm.errorMessage {
                InlineErrorView(
                    title: "Couldn't load spots",
                    message: message,
                    retry: { Task { await vm.load() } }
                )
                .padding(.top, 40)
            } else if vm.pins.isEmpty {
                EmptyStateView(
                    systemImage: "mappin.and.ellipse",
                    title: "No spots yet",
                    message: "Import your Google Maps saved places (Takeout → Saved → export as GeoJSON), then link each to Resy or OpenTable.",
                    actionTitle: "Import spots",
                    action: { showingImporter = true }
                )
                .padding(.top, 40)
            } else {
                pinList(vm)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private func pinList(_ vm: PinsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            RBSectionLabel(
                title: "SAVED SPOTS",
                count: "\(vm.linkedCount) of \(vm.pins.count) linked",
                countColor: vm.linkedCount == vm.pins.count ? RBColor.success : RBColor.textMuted
            )
            ForEach(vm.pins) { pin in
                NavigationLink {
                    LinkPinView(pin: pin, viewModel: vm)
                } label: {
                    PinRow(pin: pin)
                }
                .buttonStyle(.plain)
            }
        }
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
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RBColor.textMuted)
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
            Text("Paste the GeoJSON from Google Takeout (Saved → your list → export as GeoJSON).")
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
                Text("That doesn't look like valid GeoJSON. Paste the whole exported file.")
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
        // Client-side guard catches an obviously-wrong paste before a round-trip;
        // the server's total_parsed count is the authoritative GeoJSON validation.
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
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

