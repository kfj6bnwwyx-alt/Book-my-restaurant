import SwiftUI

/// Shown on any tab when no app key is set, or when a request comes back 401.
/// The key is global, so every screen routes the user to the same fix.
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

/// Enter the server app key (Keychain-backed, never stored in the repo).
struct ServerSettingsSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            Text("Connect")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(RBColor.textPrimary)
                .padding(.top, RBSpacing.sm)
            Text("Paste the app key from Home Assistant → Apps → ResyBooker → Configuration. It's stored in the device Keychain, never in the project.")
                .font(.system(size: 13.5))
                .foregroundStyle(RBColor.textSecondary)

            labeledRow("Server") {
                Text(AppConfig.apiBaseURL.absoluteString)
                    .font(.system(size: 14))
                    .foregroundStyle(RBColor.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            labeledRow("App key") {
                TextField("Paste app key", text: $key)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(RBColor.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }

            Spacer(minLength: 0)

            Button("Save", action: save)
                .buttonStyle(.rbPrimary)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        AppConfig.setAppKey(key)
        onSaved()
        dismiss()
    }
}

/// Reusable presentation modifier for the settings sheet.
extension View {
    func serverSettingsSheet(isPresented: Binding<Bool>, onSaved: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            ServerSettingsSheet(onSaved: onSaved)
                .presentationDetents([.height(340)])
                .presentationBackground(RBColor.surface)
                .presentationDragIndicator(.visible)
        }
    }
}
