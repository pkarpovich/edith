import Foundation
import Testing
@testable import edith

private struct ConstantProvider: AIProvider {
    let output: String
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let output = output
        return AsyncThrowingStream { continuation in
            do {
                try Task.checkCancellation()
                continuation.yield(output)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct ThrowingProvider: AIProvider {
    let error: any Error
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let error = error
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private struct DelayingProvider: AIProvider {
    let delay: Duration
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let delay = self.delay
        let prompt = prompt
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: delay)
                    continuation.yield(prompt)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

@MainActor
struct AskEdithRunnerDriveTests {
    @Test
    func successProviderTransitionsToReady() async {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ConstantProvider(output: "RESULT")
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "p",
            model: nil,
            effort: nil,
            state: state
        )
        #expect(state.state == .ready(original: "hi", result: "RESULT"))
    }

    @Test
    func providerErrorTransitionsToErrorWithFormattedMessage() async {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ThrowingProvider(error: AIProviderError.notFound)
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "p",
            model: nil,
            effort: nil,
            state: state
        )
        guard case .error(let original, let message) = state.state else {
            Issue.record("Expected .error state, got \(state.state)")
            return
        }
        #expect(original == "hi")
        #expect(message.contains("Claude CLI not found"))
    }

    @Test
    func nonZeroExitProducesErrorMessageWithCodeAndStderr() async {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ThrowingProvider(
            error: AIProviderError.nonZeroExit(code: 7, stderr: "boom")
        )
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "p",
            model: nil,
            effort: nil,
            state: state
        )
        guard case .error(_, let message) = state.state else {
            Issue.record("Expected .error state, got \(state.state)")
            return
        }
        #expect(message.contains("7"))
        #expect(message.contains("boom"))
    }

    @Test
    func cancellationKeepsProcessingState() async throws {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = DelayingProvider(delay: .seconds(5))
        let task = Task { @MainActor in
            await AskEdithRunner.drive(
                provider: provider,
                original: "hi",
                prompt: "p",
                model: nil,
                effort: nil,
                state: state
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        _ = await task.value
        #expect(state.state == .processing(original: "hi"))
    }

    @Test
    func providerThrowingAIProviderCancelledKeepsProcessingState() async {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ThrowingProvider(error: AIProviderError.cancelled)
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "p",
            model: nil,
            effort: nil,
            state: state
        )
        #expect(state.state == .processing(original: "hi"))
    }

    @Test
    func driveForwardsModelAndEffortToProvider() async {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(recorder: recorder)
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "do the thing",
            model: "haiku",
            effort: "low",
            state: state
        )
        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.prompt == "do the thing")
        #expect(calls.first?.model == "haiku")
        #expect(calls.first?.effort == "low")
    }

    @Test
    func driveForwardsNilModelAndEffortToProvider() async {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(recorder: recorder)
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "p",
            model: nil,
            effort: nil,
            state: state
        )
        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.model == nil)
        #expect(calls.first?.effort == nil)
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
    func formatPromptParserIoFailure() {
        let message = AskEdithRunner.format(
            error: PromptParserError.ioFailure(path: "/tmp/missing.txt", underlying: "no such file")
        )
        #expect(message.contains("/tmp/missing.txt"))
        #expect(message.contains("no such file"))
    }

    @Test
    func formatPromptParserUnknownVariable() {
        let message = AskEdithRunner.format(
            error: PromptParserError.unknownVariable(name: "nonsense")
        )
        #expect(message.contains("nonsense"))
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
