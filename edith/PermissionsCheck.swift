import ApplicationServices
import Foundation

enum PermissionsCheck {
    private static let axTrustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"

    static var isAccessibilityGranted: Bool {
        let options = [axTrustedCheckOptionPromptKey: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func accessibilityStatusLabel(isGranted: Bool) -> String {
        isGranted ? "Accessibility: granted" : "Accessibility: not granted"
    }
}

enum AccessibilityDeepLink {
    static let rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static var url: URL? {
        URL(string: rawValue)
    }
}
