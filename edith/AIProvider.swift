import Foundation

protocol AIProvider: Sendable {
    func run(prompt: String, model: String?, effort: String?) async throws -> String
}

enum AIProviderError: Error, Equatable, Sendable {
    case notFound
    case nonZeroExit(code: Int32, stderr: String)
    case terminatedBySignal(signal: Int32, stderr: String)
    case emptyOutput
    case cancelled
}
