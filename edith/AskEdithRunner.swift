import Foundation

nonisolated enum AskEdithRunner {
    @MainActor
    static func drive(
        provider: any AIProvider,
        input: String,
        prompt: String,
        model: OverlayStateModel
    ) async {
        do {
            let result = try await provider.run(prompt: prompt, input: input)
            try Task.checkCancellation()
            model.state = .ready(original: input, result: result)
        } catch is CancellationError {
            return
        } catch AIProviderError.cancelled {
            return
        } catch {
            model.state = .error(original: input, message: format(error: error))
        }
    }

    nonisolated static func format(error: Error) -> String {
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .notFound:
                return "Claude CLI not found. Make sure `claude` is installed and on PATH."
            case .nonZeroExit(let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? "Claude exited with code \(code)."
                    : "Claude exited with code \(code): \(trimmed)"
            case .emptyOutput:
                return "Claude returned no output."
            case .cancelled:
                return "Cancelled."
            }
        }
        return error.localizedDescription
    }
}
