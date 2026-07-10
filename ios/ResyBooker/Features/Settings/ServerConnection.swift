import SwiftUI

/// Shown when no app key is set yet.
struct ConnectServerPrompt: View {
    var action: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "key.horizontal",
            title: "Connect your server",
            message: "Enter the app key from Home Assistant (Apps → ResyBooker → Configuration) so the app can reach your booking server.",
            actionTitle: "Enter app key",
            action: action
        )
    }
}

/// A key IS set but the server returned 401 — the key is wrong, not missing.
/// Distinct message so a rejected key doesn't look like "no key".
struct AuthPrompt: View {
    var action: () -> Void

    var body: some View {
        if AppConfig.hasAppKey {
            EmptyStateView(
                systemImage: "key.slash",
                title: "App key rejected",
                message: "The server didn't accept your app key (401). Check that it matches Home Assistant, and restart the ResyBooker add-on after changing the key there.",
                actionTitle: "Update app key",
                action: action
            )
        } else {
            ConnectServerPrompt(action: action)
        }
    }
}

/// Enter the server app key (Keychain-backed, never stored in the repo). On save
/// it verifies the key against the server so a wrong key is caught immediately.
struct ServerSettingsSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            Text("Connect")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
                .padding(.top, RBSpacing.sm)
            Text("Paste the app key from Home Assistant → Apps → ResyBooker → Configuration. It's stored in the device Keychain, never in the project.")
                .font(.system(size: 13.5))
                .foregroundStyle(RBColor.textSecondary)

            labeledRow("App key") {
                TextField("Paste app key", text: $key)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(RBColor.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
            }

            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(RBColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(saving ? "Verifying…" : "Save", action: save)
                .buttonStyle(.rbPrimary)
                .disabled(saving || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .tint(RBColor.accent)
        .onAppear { if AppConfig.hasAppKey { key = AppConfig.appKey } }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(RBColor.textSecondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                        .fill(RBColor.surface2)
                )
        }
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !saving else { return }
        AppConfig.setAppKey(trimmed)
        saving = true
        error = nil
        Task {
            let result = await APIClient.shared.checkKey()
            saving = false
            switch result {
            case .ok:
                onSaved()
                dismiss()
            case .unauthorized:
                error = "The server rejected that key (401). Make sure it matches Home Assistant exactly, then restart the ResyBooker add-on (it only reads the key on start)."
            case .unreachable(let message):
                error = "Saved, but couldn't reach the server: \(message)"
            }
        }
    }
}

/// Settings menu for the Spots tab: server connection + bulk import (which is
/// secondary to adding spots one at a time, so it lives here, not in the header).
struct SettingsSheet: View {
    let viewModel: PinsViewModel
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingKey = false
    @State private var showingImport = false
    @State private var resolving = false
    @State private var resolveMessage: String?
    @State private var confirmClear = false
    @State private var clearing = false
    @State private var clearMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RBSpacing.lg) {
                        RBSectionLabel(title: "SERVER")
                        row(icon: "key.horizontal",
                            title: AppConfig.hasAppKey ? "App key" : "Enter app key",
                            detail: AppConfig.hasAppKey ? "Connected" : "Not set",
                            detailColor: AppConfig.hasAppKey ? RBColor.success : RBColor.textMuted) {
                            showingKey = true
                        }
                        RBSectionLabel(title: "PLACES")
                        row(icon: "square.and.arrow.down",
                            title: "Import from Google Takeout",
                            detail: "Bulk-add a saved list (CSV)",
                            detailColor: RBColor.textMuted) {
                            showingImport = true
                        }
                        if viewModel.unlocatedCount > 0 {
                            resolveRow
                        }
                        if viewModel.unlinkedCount > 0 || clearMessage != nil {
                            clearUnlinkedRow
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(RBColor.accent)
                }
            }
            .sheet(isPresented: $showingKey) {
                ServerSettingsSheet(onSaved: onSaved)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(RBColor.surface)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingImport) {
                ImportSheet(viewModel: viewModel) { onSaved() }
                    .presentationDetents([.large])
                    .presentationBackground(RBColor.surface)
                    .presentationDragIndicator(.visible)
            }
        }
        .tint(RBColor.accent)
    }

    private var resolveRow: some View {
        Button {
            guard !resolving else { return }
            resolving = true
            resolveMessage = nil
            Task {
                let n = await viewModel.resolveMissingLocations()
                resolveMessage = "Added a location to \(n) spot\(n == 1 ? "" : "s")"
                resolving = false
            }
        } label: {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17))
                    .foregroundStyle(RBColor.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolving ? "Resolving…" : "Resolve missing locations")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(RBColor.textPrimary)
                    Text(resolveMessage ?? "\(viewModel.unlocatedCount) spots have no location yet")
                        .font(.system(size: 12.5)).foregroundStyle(RBColor.textMuted)
                }
                Spacer()
                if resolving {
                    ProgressView().tint(RBColor.accent)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(RBColor.textMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rbCard(fill: RBColor.surface)
        }
        .buttonStyle(.plain)
        .disabled(resolving)
    }

    /// One-tap prune of bulk-import noise: deletes every spot that was never
    /// linked to a venue. Linked spots are kept; anything deleted can be
    /// re-added in seconds via search.
    private var clearUnlinkedRow: some View {
        Button {
            guard !clearing, viewModel.unlinkedCount > 0 else { return }
            confirmClear = true
        } label: {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(RBColor.red)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clearing ? "Clearing…" : "Clear unlinked spots")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(RBColor.textPrimary)
                    Text(clearMessage ?? "Delete all \(viewModel.unlinkedCount) spots not linked to a venue")
                        .font(.system(size: 12.5)).foregroundStyle(RBColor.textMuted)
                }
                Spacer()
                if clearing {
                    ProgressView().tint(RBColor.accent)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(RBColor.textMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rbCard(fill: RBColor.surface)
        }
        .buttonStyle(.plain)
        .disabled(clearing)
        .confirmationDialog(
            "Delete \(viewModel.unlinkedCount) unlinked spots?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Delete \(viewModel.unlinkedCount) spots", role: .destructive) {
                clearing = true
                Task {
                    if let n = await viewModel.clearUnlinked() {
                        clearMessage = "Deleted \(n) spot\(n == 1 ? "" : "s")"
                    }
                    clearing = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Linked spots are kept. You can re-add anything via search.")
        }
    }

    private func row(icon: String, title: String, detail: String, detailColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(RBColor.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(RBColor.textPrimary)
                    Text(detail).font(.system(size: 12.5)).foregroundStyle(detailColor)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(RBColor.textMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rbCard(fill: RBColor.surface)
        }
        .buttonStyle(.plain)
    }
}

/// Reusable presentation modifier for the settings sheet.
extension View {
    func serverSettingsSheet(isPresented: Binding<Bool>, onSaved: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            ServerSettingsSheet(onSaved: onSaved)
                .presentationDetents([.medium, .large])
                .presentationBackground(RBColor.surface)
                .presentationDragIndicator(.visible)
        }
    }
}
