import Foundation

nonisolated enum AskEdithRunner {
    static let stderrPreviewLimit: Int = 500

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
            if Task.isCancelled { return }
            model.state = .error(original: input, message: format(error: error))
        }
    }

    nonisolated static func format(error: Error) -> String {
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .notFound:
                return "Claude CLI not found. Make sure `claude` is installed and on PATH."
            case .nonZeroExit(let code, let stderr):
                let preview = stderrPreview(stderr)
                return preview.isEmpty
                    ? "Claude exited with code \(code)."
                    : "Claude exited with code \(code): \(preview)"
            case .terminatedBySignal(let signal, let stderr):
                let preview = stderrPreview(stderr)
                return preview.isEmpty
                    ? "Claude terminated by signal \(signal)."
                    : "Claude terminated by signal \(signal): \(preview)"
            case .emptyOutput:
                return "Claude returned no output."
            case .cancelled:
                return "Cancelled."
            }
        }
        return error.localizedDescription
    }

    nonisolated static func stderrPreview(_ stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > stderrPreviewLimit else { return trimmed }
        return String(trimmed.prefix(stderrPreviewLimit)) + "…"
    }
}
