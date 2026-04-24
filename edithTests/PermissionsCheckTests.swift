import Testing
import Foundation
@testable import edith

struct PermissionsCheckTests {
    @Test
    func accessibilityDeepLinkRawValueMatchesExpected() {
        #expect(
            AccessibilityDeepLink.rawValue
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    @Test
    func accessibilityDeepLinkProducesValidURL() {
        let url = AccessibilityDeepLink.url
        #expect(url != nil)
        #expect(url?.scheme == "x-apple.systempreferences")
    }

    @Test
    func statusLabelForGrantedIsGranted() {
        #expect(PermissionsCheck.accessibilityStatusLabel(isGranted: true) == "Accessibility: granted")
    }

    @Test
    func statusLabelForDeniedIsNotGranted() {
        #expect(PermissionsCheck.accessibilityStatusLabel(isGranted: false) == "Accessibility: not granted")
    }
}
