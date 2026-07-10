import SwiftUI

// ResyBooker design tokens, generated from the Pencil design system.
// Dark-only by design: an evening, one-handed monitoring tool. Cool-tinted
// neutrals, signal orange for actions/selection, green for availability/success.

extension Color {
    /// Hex initializer supporting #RGB, #RRGGBB, and #RRGGBBAA (with or without #).
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 3: (r, g, b, a) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17, 255)
        case 6: (r, g, b, a) = (value >> 16, value >> 8 & 0xFF, value & 0xFF, 255)
        case 8: (r, g, b, a) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: (r, g, b, a) = (236, 238, 242, 255)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

enum RBColor {
    // Neutrals (cool-tinted)
    static let bg = Color(hex: "16171A")
    static let surface = Color(hex: "1F2125")
    static let surface2 = Color(hex: "292B30")
    static let border = Color(hex: "383B42")
    static let scrim = Color(hex: "0D0E10")

    // Text
    static let textPrimary = Color(hex: "ECEEF2")
    static let textSecondary = Color(hex: "A0A4AD")
    static let textMuted = Color(hex: "90949E")

    // Accent: signal orange (actions, selection, brand)
    static let accent = Color(hex: "F26A35")
    static let accentInk = Color(hex: "1E1206")
    static let accentSoft = Color(hex: "3A2415")

    // Success: green (availability, confirmed, on-state)
    static let success = Color(hex: "58CC8B")
    static let successSoft = Color(hex: "1E3A2A")

    // Warning / error
    static let amber = Color(hex: "E0A852")
    static let amberSoft = Color(hex: "3A2F1C")
    static let red = Color(hex: "E0685C")
    static let redSoft = Color(hex: "3A2320")
}

enum RBRadius {
    static let card: CGFloat = 16
    static let small: CGFloat = 12
    static let pill: CGFloat = 999
}

enum RBSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
    static let section: CGFloat = 28
}
