import AppIntents
import Foundation
import os

struct AskEdithIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Edith"
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Prompt file",
        description: "Absolute path to a prompt file with optional YAML frontmatter (model, effort) and `{{selection}}` placeholder."
    )
    var path: String

    func perform() async throws -> some IntentResult {
        Logger.edith.info("AskEdithIntent.perform fired at \(Date().timeIntervalSince1970, privacy: .public)")
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            Logger.edith.info("AskEdithIntent: path parameter is empty")
            return .result()
        }
        let reader = SelectionReader()
        guard let selection = reader.readSelectedText(), !selection.isEmpty else {
            Logger.edith.info("AskEdithIntent: no selection captured")
            return .result()
        }
        let preview = String(selection.prefix(200))
        Logger.edith.info("AskEdithIntent selection: \(preview, privacy: .private)")

        let coordinator = await MainActor.run {
            OverlayCoordinator(initial: .processing(original: selection))
        }

        let prepared: PreparedPrompt
        do {
            prepared = try Self.prepare(path: trimmedPath, selection: selection)
        } catch {
            let message = AskEdithRunner.format(error: error)
            await MainActor.run {
                coordinator.model.state = .error(original: selection, message: message)
            }
            _ = await coordinator.present()
            return .result()
        }

        let provider = ClaudeCLIProvider()

        let driveTask = Task { @MainActor in
            await AskEdithRunner.drive(
                provider: provider,
                original: selection,
                prompt: prepared.rendered,
                model: prepared.model,
                effort: prepared.effort,
                state: coordinator.model
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

    nonisolated static func prepare(path: String, selection: String) throws -> PreparedPrompt {
        let contents = try PromptFileLoader.load(path: path)
        let definition = PromptDefinition.parse(contents: contents)
        let rendered = try PromptDefinition.render(
            definition: definition,
            variables: ["selection": selection]
        )
        return PreparedPrompt(
            rendered: rendered,
            model: definition.model.map(PromptDefinition.normalizeModel),
            effort: definition.effort
        )
    }

    nonisolated struct PreparedPrompt: Sendable, Equatable {
        let rendered: String
        let model: String?
        let effort: String?
    }
}
