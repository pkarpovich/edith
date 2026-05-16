import Foundation

protocol AIProvider: Sendable {
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error>
}

enum AIProviderError: Error, Equatable, Sendable, LocalizedError {
    case notFound
    case nonZeroExit(code: Int32, stderr: String)
    case terminatedBySignal(signal: Int32, stderr: String)
    case emptyOutput
    case cancelled
    case missingApiKey
    case apiError(status: Int, type: String, message: String)
    case truncatedStream

    private static let stderrPreviewLimit: Int = 500

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude CLI not found. Make sure `claude` is installed and on PATH."
        case .nonZeroExit(let code, let stderr):
            let preview = Self.stderrPreview(stderr)
            return preview.isEmpty
                ? "Claude exited with code \(code)."
                : "Claude exited with code \(code): \(preview)"
        case .terminatedBySignal(let signal, let stderr):
            let preview = Self.stderrPreview(stderr)
            return preview.isEmpty
                ? "Claude terminated by signal \(signal)."
                : "Claude terminated by signal \(signal): \(preview)"
        case .emptyOutput:
            return "Provider returned no output."
        case .cancelled:
            return "Cancelled."
        case .missingApiKey:
            return "Anthropic API key missing - open Settings (Cmd+,) to add it."
        case .apiError(let status, let type, let message):
            let preview = Self.stderrPreview(message)
            return "Anthropic API error (\(status) \(type)): \(preview)"
        case .truncatedStream:
            return "Anthropic API stream ended unexpectedly before completion."
        }
    }

    static func stderrPreview(_ stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > stderrPreviewLimit else { return trimmed }
        return String(trimmed.prefix(stderrPreviewLimit)) + "…"
    }
}
