import SwiftUI

enum DesignTokens {
    enum Window {
        static let width: CGFloat = 560
        static let radius: CGFloat = 14
    }

    enum Header {
        static let horizontalPadding: CGFloat = 14
        static let topPadding: CGFloat = 10
        static let bottomPadding: CGFloat = 8
        static let markSize: CGFloat = 14
        static let markRadius: CGFloat = 4
    }

    enum Body {
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 14
        static let bodyFontSize: CGFloat = 13
        static let bodyLineSpacing: CGFloat = 6
        static let maxHeight: CGFloat = 440
    }

    enum Footer {
        static let horizontalPadding: CGFloat = 12
        static let topPadding: CGFloat = 7
        static let bottomPadding: CGFloat = 8
        static let fontSize: CGFloat = 11
    }

    enum Keycap {
        static let height: CGFloat = 18
        static let minWidth: CGFloat = 18
        static let horizontalPadding: CGFloat = 5
        static let radius: CGFloat = 4
        static let fontSize: CGFloat = 10.5
    }

    enum Chip {
        static let horizontalPadding: CGFloat = 7
        static let verticalPadding: CGFloat = 3
        static let radius: CGFloat = 4
        static let fontSize: CGFloat = 11
    }

    enum Diff {
        static let radius: CGFloat = 2
        static let horizontalPadding: CGFloat = 1
    }
}

enum Palette {
    static func windowBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 34/255, green: 32/255, blue: 40/255).opacity(0.62)
            : Color(red: 252/255, green: 250/255, blue: 245/255).opacity(0.78)
    }

    static func windowStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    static func windowInnerStrokeTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85)
    }

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0xEC/255, green: 0xED/255, blue: 0xF2/255)
            : Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1D/255)
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0xA5/255, green: 0xA6/255, blue: 0xB0/255)
            : Color(red: 0x6B/255, green: 0x6B/255, blue: 0x70/255)
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    static func fillSubtle(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    static func footerBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.35)
    }

    static func accentGreen(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0x5D/255, green: 0xD6/255, blue: 0x84/255)
            : Color(red: 0x2E/255, green: 0xA0/255, blue: 0x43/255)
    }

    static func accentGreenSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 64/255, green: 200/255, blue: 110/255).opacity(0.22)
            : Color(red: 46/255, green: 160/255, blue: 67/255).opacity(0.18)
    }

    static func accentGreenLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0xCD/255, green: 0xF5/255, blue: 0xD6/255)
            : Color(red: 0x0A/255, green: 0x4A/255, blue: 0x1B/255)
    }

    static func accentGreenKeycapBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 64/255, green: 200/255, blue: 110/255).opacity(0.22)
            : Color(red: 46/255, green: 160/255, blue: 67/255).opacity(0.16)
    }

    static func accentGreenKeycapStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 72/255, green: 220/255, blue: 120/255).opacity(0.38)
            : Color(red: 46/255, green: 160/255, blue: 67/255).opacity(0.28)
    }

    static func error(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
            : Color(red: 0xDC/255, green: 0x26/255, blue: 0x26/255)
    }

    static func errorBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 248/255, green: 113/255, blue: 113/255).opacity(0.14)
            : Color(red: 220/255, green: 38/255, blue: 38/255).opacity(0.10)
    }

    static func errorLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0xFC/255, green: 0xA5/255, blue: 0xA5/255)
            : Color(red: 0xA0/255, green: 0x19/255, blue: 0x19/255)
    }

    static func errorBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 248/255, green: 113/255, blue: 113/255).opacity(0.30)
            : Color(red: 220/255, green: 38/255, blue: 38/255).opacity(0.22)
    }

    static let brandMarkGradient = LinearGradient(
        colors: [
            Color(red: 0x2E/255, green: 0xA0/255, blue: 0x43/255),
            Color(red: 0x1A/255, green: 0x75/255, blue: 0x31/255),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
