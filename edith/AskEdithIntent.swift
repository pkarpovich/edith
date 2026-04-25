import AppIntents
import Foundation
import os

struct AskEdithIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Edith"
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Prompt", description: "Instruction sent to Claude.")
    var prompt: String

    func perform() async throws -> some IntentResult {
        Logger.edith.info("AskEdithIntent.perform fired at \(Date().timeIntervalSince1970, privacy: .public)")
        let reader = SelectionReader()
        guard let selection = reader.readSelectedText() else {
            Logger.edith.info("AskEdithIntent: no selection captured")
            return .result()
        }
        let preview = String(selection.prefix(200))
        Logger.edith.info("AskEdithIntent selection: \(preview, privacy: .private)")

        let coordinator = await MainActor.run {
            OverlayCoordinator(initial: .processing(original: selection))
        }
        let provider = ClaudeCLIProvider()
        let capturedPrompt = prompt

        let driveTask = Task { @MainActor in
            await AskEdithRunner.drive(
                provider: provider,
                input: selection,
                prompt: capturedPrompt,
                model: coordinator.model
            )
        }

        let outcome = await coordinator.present()
        driveTask.cancel()
        _ = await driveTask.value

        switch outcome {
        case .confirmed(let text):
            Logger.edith.info("AskEdithIntent confirmed: \(String(text.prefix(200)), privacy: .private)")
        case .dismissed:
            Logger.edith.info("AskEdithIntent dismissed")
        }
        return .result()
    }
}
