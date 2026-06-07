import Foundation

enum AppConfig {
    // Live backend: Home Assistant add-on fronted by the Cloudflare tunnel.
    static let apiBaseURL = URL(string: "https://resy.brentbrooks.com")!

    // Must match `app_key` in the HA add-on Configuration tab (sent as X-App-Key).
    // For a sideloaded personal app this is fine in source; if you ever share
    // builds, move it to Keychain and set it once on first launch instead.
    // TODO: paste the real key from HA → Apps → ResyBooker → Configuration.
    static let appKey = "PASTE_APP_KEY_FROM_HA_ADDON_CONFIG"
}
