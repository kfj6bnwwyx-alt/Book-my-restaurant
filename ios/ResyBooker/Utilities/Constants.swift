import Foundation

enum AppConfig {
    // Live backend: Home Assistant add-on fronted by the Cloudflare tunnel.
    static let apiBaseURL = URL(string: "https://resy.brentbrooks.com")!

    private static let placeholderKey = "PASTE_APP_KEY_FROM_HA_ADDON_CONFIG"
    private static let keychainAccount = "appKey"

    /// Sent as the `X-App-Key` header; must match the HA add-on's `app_key`.
    /// Stored in the Keychain and entered in-app (Spots → settings), never in
    /// this repo — it is public. Falls back to the placeholder when unset, which
    /// the server rejects with 401 until a real key is entered.
    static var appKey: String {
        KeychainStore.shared.string(for: keychainAccount) ?? placeholderKey
    }

    /// True once a real key (not the placeholder) has been stored.
    static var hasAppKey: Bool {
        let key = appKey
        return !key.isEmpty && key != placeholderKey
    }

    static func setAppKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.shared.set(trimmed.isEmpty ? nil : trimmed, for: keychainAccount)
    }
}
