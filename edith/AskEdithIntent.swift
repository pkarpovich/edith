import AppIntents
import Foundation
import os

struct AskEdithIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Edith"
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        Logger.edith.info("AskEdithIntent.perform fired at \(Date().timeIntervalSince1970, privacy: .public)")
        let reader = SelectionReader()
        if let selection = reader.readSelectedText() {
            let preview = String(selection.prefix(200))
            Logger.edith.info("AskEdithIntent selection: \(preview, privacy: .private)")
        } else {
            Logger.edith.info("AskEdithIntent: no selection captured")
        }
        return .result()
    }
}
