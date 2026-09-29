import Foundation
import os
import SwiftData

@MainActor
final class RunRecorder {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func start(
        promptPath: String,
        promptName: String?,
        provider: ProviderKind,
        model: String?,
        effort: String?,
        original: String
    ) -> EditRun {
        let run = EditRun(
            promptPath: promptPath,
            promptName: promptName,
            provider: provider.rawValue,
            model: model,
            effort: effort,
            original: original
        )
        context.insert(run)
        save()
        return run
    }

    func finish(_ run: EditRun, with outcome: DriveOutcome) {
        switch outcome {
        case .finished(let response, let latencySeconds):
            run.rawOutput = response.rawOutput
            run.result = response.text
            run.stopReason = response.stopReason
            run.latencySeconds = latencySeconds
        case .failed(let message, let rawOutput, let latencySeconds):
            run.rawOutput = rawOutput
            run.latencySeconds = latencySeconds
            run.errorMessage = message
            run.outcome = .failed
        case .cancelled:
            return
        }
        save()
    }

    func recordFailure(promptPath: String, promptName: String?, original: String, message: String) {
        let run = EditRun(
            promptPath: promptPath,
            promptName: promptName,
            provider: nil,
            model: nil,
            effort: nil,
            original: original,
            outcome: .failed
        )
        run.errorMessage = message
        context.insert(run)
        save()
    }

    func resolve(_ run: EditRun, as outcome: RunOutcome) {
        run.outcome = outcome
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Logger.edith.error("RunRecorder: save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
