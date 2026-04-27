import Foundation

protocol AIProvider: Sendable {
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error>
}

enum AIProviderError: Error, Equatable, Sendable {
    case notFound
    case nonZeroExit(code: Int32, stderr: String)
    case terminatedBySignal(signal: Int32, stderr: String)
    case emptyOutput
    case cancelled
    case missingApiKey
    case apiError(status: Int, type: String, message: String)
}
