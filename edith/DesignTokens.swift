import AppKit
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
        static let maxHeight: CGFloat = 440
    }

    enum Footer {
        static let horizontalPadding: CGFloat = 12
        static let topPadding: CGFloat = 7
        static let bottomPadding: CGFloat = 8
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
    }

    enum Diff {
        static let radius: CGFloat = 2
        static let horizontalPadding: CGFloat = 1
    }
}

extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil ? dark : light
        })
    }
}

extension Color {
    static let edithDiffBackground: Color = .dynamic(
        light: NSColor(srgbRed: 46/255, green: 160/255, blue: 67/255, alpha: 0.18),
        dark: NSColor(srgbRed: 64/255, green: 200/255, blue: 110/255, alpha: 0.22)
    )

    static let edithDiffForeground: Color = .dynamic(
        light: NSColor(srgbRed: 0x0A/255, green: 0x4A/255, blue: 0x1B/255, alpha: 1),
        dark: NSColor(srgbRed: 0xCD/255, green: 0xF5/255, blue: 0xD6/255, alpha: 1)
    )

    static let edithAccentKeycapBackground: Color = .dynamic(
        light: NSColor(srgbRed: 46/255, green: 160/255, blue: 67/255, alpha: 0.16),
        dark: NSColor(srgbRed: 64/255, green: 200/255, blue: 110/255, alpha: 0.22)
    )

    static let edithAccentKeycapStroke: Color = .dynamic(
        light: NSColor(srgbRed: 46/255, green: 160/255, blue: 67/255, alpha: 0.28),
        dark: NSColor(srgbRed: 72/255, green: 220/255, blue: 120/255, alpha: 0.38)
    )

    static let edithErrorBackground: Color = .dynamic(
        light: NSColor(srgbRed: 220/255, green: 38/255, blue: 38/255, alpha: 0.10),
        dark: NSColor(srgbRed: 248/255, green: 113/255, blue: 113/255, alpha: 0.14)
    )

    static let edithErrorLabel: Color = .dynamic(
        light: NSColor(srgbRed: 0xA0/255, green: 0x19/255, blue: 0x19/255, alpha: 1),
        dark: NSColor(srgbRed: 0xFC/255, green: 0xA5/255, blue: 0xA5/255, alpha: 1)
    )

    static let edithErrorBorder: Color = .dynamic(
        light: NSColor(srgbRed: 220/255, green: 38/255, blue: 38/255, alpha: 0.22),
        dark: NSColor(srgbRed: 248/255, green: 113/255, blue: 113/255, alpha: 0.30)
    )

}

enum Brand {
    static let markGradient = LinearGradient(
        colors: [
            Color(red: 0x2E/255, green: 0xA0/255, blue: 0x43/255),
            Color(red: 0x1A/255, green: 0x75/255, blue: 0x31/255),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
