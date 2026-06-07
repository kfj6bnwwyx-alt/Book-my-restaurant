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
