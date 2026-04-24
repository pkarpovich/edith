import Testing
import AppIntents
@testable import edith

struct AskEdithIntentTests {
    @Test
    func titleIsAskEdith() {
        #expect(String(localized: AskEdithIntent.title) == "Ask Edith")
    }

    @Test
    func supportedModesIsBackground() {
        #expect(AskEdithIntent.supportedModes == .background)
    }
}
