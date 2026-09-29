import AppIntents
import Foundation
import os
import SwiftData

struct AskEdithIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Edith"
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Prompt file",
        description: "Absolute path to a prompt file with optional YAML frontmatter (model, effort) and `{{selection}}` placeholder."
    )
    var path: String

    @Dependency private var container: ModelContainer

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

        let promptName = Self.promptName(from: trimmedPath)
        let recorder = await MainActor.run { RunRecorder(context: container.mainContext) }

        let prepared: PreparedPrompt
        do {
            prepared = try Self.prepare(path: trimmedPath, selection: selection)
        } catch {
            let message = error.localizedDescription
            await recorder.recordFailure(
                promptPath: trimmedPath,
                promptName: promptName,
                original: selection,
                message: message
            )
            let coordinator = await MainActor.run {
                OverlayCoordinator(
                    initial: .error(original: selection, message: message),
                    promptName: promptName,
                    modelLabel: nil
                )
            }
            _ = await coordinator.present()
            return .result()
        }

        let modelLabel = Self.modelLabel(provider: prepared.provider, model: prepared.model)

        let coordinator = await MainActor.run {
            OverlayCoordinator(
                initial: .processing(original: selection),
                promptName: promptName,
                modelLabel: modelLabel
            )
        }

        let latestRun = await MainActor.run { LatestRun() }
        let drive: @MainActor () async -> Void = { @MainActor in
            let run = recorder.start(
                promptPath: trimmedPath,
                promptName: promptName,
                provider: prepared.provider,
                model: prepared.model,
                effort: prepared.effort,
                original: selection
            )
            latestRun.run = run
            let provider = Self.makeProvider(kind: prepared.provider)
            let outcome = await AskEdithRunner.drive(
                provider: provider,
                original: selection,
                prompt: prepared.rendered,
                model: prepared.model,
                effort: prepared.effort,
                state: coordinator.model
            )
            recorder.finish(run, with: outcome)
        }

        let outcome = await coordinator.present(drive: drive)

        switch outcome {
        case .confirmed(let text):
            Logger.edith.info("AskEdithIntent confirmed: \(String(text.prefix(200)), privacy: .private)")
        case .pasteFailed(let text):
            Logger.edith.error("AskEdithIntent paste failed: \(String(text.prefix(200)), privacy: .private)")
        case .dismissed:
            Logger.edith.info("AskEdithIntent dismissed")
        }
        await MainActor.run {
            guard let run = latestRun.run else { return }
            recorder.resolve(run, as: Self.runOutcome(for: outcome))
        }
        return .result()
    }

    nonisolated static func runOutcome(for outcome: OverlayCoordinator.Outcome) -> RunOutcome {
        switch outcome {
        case .confirmed: .confirmed
        case .pasteFailed: .pasteFailed
        case .dismissed: .dismissed
        }
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
            model: definition.model,
            effort: definition.effort,
            provider: definition.provider
        )
    }

    nonisolated static func promptName(from path: String) -> String? {
        let basename = (path as NSString).lastPathComponent
        let stem = (basename as NSString).deletingPathExtension
        let trimmed = stem.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func modelLabel(provider: ProviderKind, model: String?) -> String {
        let resolved = model?.isEmpty == false ? model! : "default"
        let providerLabel: String = {
            switch provider {
            case .cli: return "claude · cli"
            case .api: return "claude · api"
            }
        }()
        return "\(providerLabel) · \(resolved)"
    }

    @MainActor
    static func makeProvider(kind: ProviderKind) -> any AIProvider {
        switch kind {
        case .cli:
            return ClaudeCLIProvider()
        case .api:
            return AnthropicAPIProvider(transport: URLSessionAnthropicTransport())
        }
    }

    @MainActor
    private final class LatestRun {
        var run: EditRun?
    }

    nonisolated struct PreparedPrompt: Sendable, Equatable {
        let rendered: String
        let model: String?
        let effort: String?
        let provider: ProviderKind
    }
}
