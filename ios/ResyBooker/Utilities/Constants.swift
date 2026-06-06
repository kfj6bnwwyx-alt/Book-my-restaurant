import Foundation

enum AppConfig {
    // Point at your Caddy-fronted VPS endpoint.
    static let apiBaseURL = URL(string: "https://resy.brentbrooks.com")!

    // Must match APP_KEY in the server .env. For a sideloaded personal app this
    // is fine in source; if you ever share builds, move it to Keychain and set
    // it once on first launch instead.
    static let appKey = "change-me-to-match-server"
}
