import AppIntents
import Foundation
import os

struct AskEdithIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Edith"
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        Logger.edith.info("AskEdithIntent.perform fired at \(Date().timeIntervalSince1970, privacy: .public)")
        return .result()
    }
}
