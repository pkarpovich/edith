import Foundation

nonisolated enum AskEdithRunner {
    @MainActor
    static func drive(
        provider: any AIProvider,
        original: String,
        prompt: String,
        model: String?,
        effort: String?,
        state: OverlayStateModel
    ) async {
        do {
            var result = ""
            for try await chunk in provider.run(prompt: prompt, model: model, effort: effort) {
                try Task.checkCancellation()
                result += chunk
                state.state = .streaming(original: original, partial: result)
            }
            try Task.checkCancellation()
            state.state = .ready(original: original, result: result)
        } catch is CancellationError {
            return
        } catch AIProviderError.cancelled {
            return
        } catch {
            if Task.isCancelled { return }
            state.state = .error(original: original, message: error.localizedDescription)
        }
    }
}
