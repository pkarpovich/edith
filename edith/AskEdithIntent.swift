import AppIntents
import Foundation
import os

struct AskEdithIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Edith"
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        Logger.edith.info("AskEdithIntent.perform fired at \(Date().timeIntervalSince1970, privacy: .public)")
        let reader = SelectionReader()
        guard let selection = reader.readSelectedText() else {
            Logger.edith.info("AskEdithIntent: no selection captured")
            return .result()
        }
        let preview = String(selection.prefix(200))
        Logger.edith.info("AskEdithIntent selection: \(preview, privacy: .private)")

        let transformed = MockTransformer.transform(selection)

        let coordinator = await MainActor.run { OverlayCoordinator() }
        let outcome = await coordinator.present(original: selection, result: transformed)
        switch outcome {
        case .confirmed(let text):
            Logger.edith.info("AskEdithIntent confirmed: \(String(text.prefix(200)), privacy: .private)")
        case .dismissed:
            Logger.edith.info("AskEdithIntent dismissed")
        }
        return .result()
    }
}
