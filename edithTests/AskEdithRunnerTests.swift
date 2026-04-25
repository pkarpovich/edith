import Foundation
import Testing
@testable import edith

private struct ConstantProvider: AIProvider {
    let output: String
    func run(prompt: String, model: String?, effort: String?) async throws -> String {
        try Task.checkCancellation()
        return output
    }
}

private struct ThrowingProvider: AIProvider {
    let error: any Error
    func run(prompt: String, model: String?, effort: String?) async throws -> String {
        throw error
    }
}

private struct DelayingProvider: AIProvider {
    let delay: Duration
    func run(prompt: String, model: String?, effort: String?) async throws -> String {
        try await Task.sleep(for: delay)
        return prompt
    }
}

@MainActor
struct AskEdithRunnerDriveTests {
    @Test
    func successProviderTransitionsToReady() async {
        let model = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ConstantProvider(output: "RESULT")
        await AskEdithRunner.drive(
            provider: provider,
            input: "hi",
            prompt: "p",
            model: model
        )
        #expect(model.state == .ready(original: "hi", result: "RESULT"))
    }

    @Test
    func providerErrorTransitionsToErrorWithFormattedMessage() async {
        let model = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ThrowingProvider(error: AIProviderError.notFound)
        await AskEdithRunner.drive(
            provider: provider,
            input: "hi",
            prompt: "p",
            model: model
        )
        guard case .error(let original, let message) = model.state else {
            Issue.record("Expected .error state, got \(model.state)")
            return
        }
        #expect(original == "hi")
        #expect(message.contains("Claude CLI not found"))
    }

    @Test
    func nonZeroExitProducesErrorMessageWithCodeAndStderr() async {
        let model = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ThrowingProvider(
            error: AIProviderError.nonZeroExit(code: 7, stderr: "boom")
        )
        await AskEdithRunner.drive(
            provider: provider,
            input: "hi",
            prompt: "p",
            model: model
        )
        guard case .error(_, let message) = model.state else {
            Issue.record("Expected .error state, got \(model.state)")
            return
        }
        #expect(message.contains("7"))
        #expect(message.contains("boom"))
    }

    @Test
    func cancellationKeepsProcessingState() async throws {
        let model = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = DelayingProvider(delay: .seconds(5))
        let task = Task { @MainActor in
            await AskEdithRunner.drive(
                provider: provider,
                input: "hi",
                prompt: "p",
                model: model
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        _ = await task.value
        #expect(model.state == .processing(original: "hi"))
    }

    @Test
    func providerThrowingAIProviderCancelledKeepsProcessingState() async {
        let model = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ThrowingProvider(error: AIProviderError.cancelled)
        await AskEdithRunner.drive(
            provider: provider,
            input: "hi",
            prompt: "p",
            model: model
        )
        #expect(model.state == .processing(original: "hi"))
    }
}

struct AskEdithRunnerFormatTests {
    @Test
    func formatNotFound() {
        let message = AskEdithRunner.format(error: AIProviderError.notFound)
        #expect(message.contains("Claude CLI not found"))
        #expect(message.contains("PATH"))
    }

    @Test
    func formatNonZeroExitWithStderr() {
        let message = AskEdithRunner.format(
            error: AIProviderError.nonZeroExit(code: 42, stderr: "kaboom")
        )
        #expect(message.contains("42"))
        #expect(message.contains("kaboom"))
    }

    @Test
    func formatNonZeroExitWithEmptyStderr() {
        let message = AskEdithRunner.format(
            error: AIProviderError.nonZeroExit(code: 1, stderr: "")
        )
        #expect(message == "Claude exited with code 1.")
    }

    @Test
    func formatTerminatedBySignal() {
        let message = AskEdithRunner.format(
            error: AIProviderError.terminatedBySignal(signal: 15, stderr: "killed")
        )
        #expect(message.contains("signal 15"))
        #expect(message.contains("killed"))
    }

    @Test
    func formatTerminatedBySignalEmptyStderr() {
        let message = AskEdithRunner.format(
            error: AIProviderError.terminatedBySignal(signal: 9, stderr: "")
        )
        #expect(message == "Claude terminated by signal 9.")
    }

    @Test
    func formatTruncatesLongStderr() {
        let long = String(repeating: "x", count: 1200)
        let message = AskEdithRunner.format(
            error: AIProviderError.nonZeroExit(code: 1, stderr: long)
        )
        #expect(message.count < long.count)
        #expect(message.hasSuffix("…"))
    }

    @Test
    func formatEmptyOutput() {
        let message = AskEdithRunner.format(error: AIProviderError.emptyOutput)
        #expect(message.contains("no output"))
    }

    @Test
    func formatCancelled() {
        let message = AskEdithRunner.format(error: AIProviderError.cancelled)
        #expect(message == "Cancelled.")
    }

    @Test
    func formatUnknownErrorFallsBackToLocalizedDescription() {
        struct CustomError: LocalizedError {
            var errorDescription: String? { "custom-message" }
        }
        let message = AskEdithRunner.format(error: CustomError())
        #expect(message == "custom-message")
    }
}
