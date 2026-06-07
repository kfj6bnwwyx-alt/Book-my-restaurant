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
            iconButton("square.and.arrow.down", label: "Import spots") { showingImporter = true }
        }
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RBColor.accent)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .fill(RBColor.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                                .stroke(RBColor.border, lineWidth: 1)
                        )
                )
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
        .background(
            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                .fill(RBColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .stroke(RBColor.border, lineWidth: 1)
                )
        )
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
        .background(
            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                .fill(RBColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .stroke(RBColor.border, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Import sheet

struct ImportSheet: View {
    let viewModel: PinsViewModel
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var invalid = false
    @State private var importing = false
    @State private var serverError: String?

    var body: some View {
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
                .frame(minHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .fill(RBColor.surface2)
                        .overlay(
                            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                                .stroke(invalid ? RBColor.red : RBColor.border, lineWidth: 1)
                        )
                )

            if invalid {
                inlineMessage("That doesn't look like valid GeoJSON. Export your list from Google Takeout as GeoJSON and paste the whole file.", color: RBColor.red)
            } else if let serverError {
                inlineMessage(serverError, color: RBColor.amber)
            }

            Button(importing ? "Importing…" : "Import", action: runImport)
                .buttonStyle(.rbPrimary)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importing)
        }
        .padding(20)
        .tint(RBColor.accent)
    }

    private func inlineMessage(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func runImport() {
        invalid = false
        serverError = nil
        // Client-side guard so an obviously-wrong paste gets a clear message
        // instead of a server round-trip / opaque 500.
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            invalid = true
            return
        }
        importing = true
        Task {
            let ok = await viewModel.importGeoJSON(text)
            importing = false
            if ok {
                onSuccess()
                dismiss()
            } else {
                serverError = viewModel.errorMessage ?? "Import failed."
            }
        }
    }
}

