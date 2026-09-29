import Foundation

nonisolated enum DriveOutcome: Sendable, Equatable {
    case finished(ProviderResponse, latencySeconds: Double)
    case failed(message: String, rawOutput: String?, latencySeconds: Double)
    case cancelled
}

nonisolated enum AskEdithRunner {
    @MainActor
    @discardableResult
    static func drive(
        provider: any AIProvider,
        original: String,
        prompt: String,
        model: String?,
        effort: String?,
        state: OverlayStateModel
    ) async -> DriveOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            var partial = ""
            for try await event in provider.run(prompt: prompt, model: model, effort: effort) {
                try Task.checkCancellation()
                switch event {
                case .partial(let chunk):
                    partial += chunk
                    state.state = .streaming(original: original, partial: partial)
                case .finished(let response):
                    state.state = .ready(original: original, result: response.text)
                    return .finished(response, latencySeconds: (clock.now - start) / .seconds(1))
                }
            }
            throw AIProviderError.truncatedStream
        } catch is CancellationError {
            return .cancelled
        } catch AIProviderError.cancelled {
            return .cancelled
        } catch {
            if Task.isCancelled { return .cancelled }
            let message = error.localizedDescription
            state.state = .error(original: original, message: message)
            return .failed(
                message: message,
                rawOutput: (error as? AIProviderError)?.rawOutput,
                latencySeconds: (clock.now - start) / .seconds(1)
            )
        }
    }
}
