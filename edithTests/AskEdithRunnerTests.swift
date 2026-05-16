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

private struct ChunkedProvider: AIProvider {
    let chunks: [String]
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let chunks = chunks
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                    await Task.yield()
                }
                continuation.finish()
            }
        }
    }
}

private struct ChunkThenErrorProvider: AIProvider {
    let chunks: [String]
    let error: any Error
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let chunks = chunks
        let error = error
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                    await Task.yield()
                }
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct InfiniteChunkProvider: AIProvider {
    let chunk: String
    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let chunk = chunk
        return AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(chunk)
                    do {
                        try await Task.sleep(for: .milliseconds(5))
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

@MainActor
private final class OverlayStateRecorder {
    private(set) var states: [OverlayState] = []
    private weak var model: OverlayStateModel?

    init(model: OverlayStateModel) {
        self.model = model
        states.append(model.state)
        rearm()
    }

    private func rearm() {
        withObservationTracking {
            _ = model?.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let model = self.model else { return }
                self.states.append(model.state)
                self.rearm()
            }
        }
    }

    func flush() async {
        for _ in 0..<20 { await Task.yield() }
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
    func driveTransitionsThroughStreamingStatesForEachChunk() async {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let recorder = OverlayStateRecorder(model: state)
        let provider = ChunkedProvider(chunks: ["he", "llo"])
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "p",
            model: nil,
            effort: nil,
            state: state
        )
        await recorder.flush()
        #expect(state.state == .ready(original: "hi", result: "hello"))
        #expect(recorder.states.first == .processing(original: "hi"))
        #expect(recorder.states.contains(.streaming(original: "hi", partial: "he")))
        #expect(recorder.states.contains(.streaming(original: "hi", partial: "hello")))
        #expect(recorder.states.last == .ready(original: "hi", result: "hello"))
    }

    @Test
    func driveTransitionsToStreamingThenReadyWithSingleChunk() async {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let recorder = OverlayStateRecorder(model: state)
        let provider = ChunkedProvider(chunks: ["RESULT"])
        await AskEdithRunner.drive(
            provider: provider,
            original: "hi",
            prompt: "p",
            model: nil,
            effort: nil,
            state: state
        )
        await recorder.flush()
        #expect(state.state == .ready(original: "hi", result: "RESULT"))
        #expect(recorder.states.contains(.streaming(original: "hi", partial: "RESULT")))
    }

    @Test
    func driveTransitionsToErrorWhenStreamThrowsMidStream() async {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = ChunkThenErrorProvider(
            chunks: ["partial"],
            error: AIProviderError.notFound
        )
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
    func driveCancellationMidStreamDoesNotFlipToTerminalState() async throws {
        let state = OverlayStateModel(initial: .processing(original: "hi"))
        let provider = InfiniteChunkProvider(chunk: "x")
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
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        _ = await task.value
        switch state.state {
        case .processing, .streaming:
            break
        default:
            Issue.record("Expected non-terminal state after cancellation, got \(state.state)")
        }
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

struct AskEdithErrorMessageTests {
    @Test(arguments: [
        (AIProviderError.notFound,                                                      ["Claude CLI not found", "PATH"]),
        (.nonZeroExit(code: 42, stderr: "kaboom"),                                      ["42", "kaboom"]),
        (.terminatedBySignal(signal: 15, stderr: "killed"),                             ["signal 15", "killed"]),
        (.emptyOutput,                                                                  ["no output"]),
        (.missingApiKey,                                                                ["Settings"]),
        (.apiError(status: 429, type: "rate_limit_error", message: "too many requests"), ["429", "rate_limit_error", "too many requests"]),
        (.truncatedStream,                                                              ["stream ended"]),
    ] as [(AIProviderError, [String])])
    func aiProviderErrorContainsExpectedFragments(error: AIProviderError, fragments: [String]) {
        let message = error.localizedDescription
        for fragment in fragments {
            #expect(message.contains(fragment), "expected '\(fragment)' in '\(message)'")
        }
    }

    @Test(arguments: [
        (AIProviderError.nonZeroExit(code: 1, stderr: ""),         "Claude exited with code 1."),
        (.terminatedBySignal(signal: 9, stderr: ""),               "Claude terminated by signal 9."),
        (.cancelled,                                               "Cancelled."),
    ] as [(AIProviderError, String)])
    func aiProviderErrorExactMessage(error: AIProviderError, expected: String) {
        #expect(error.localizedDescription == expected)
    }

    @Test
    func nonZeroExitTruncatesLongStderr() {
        let long = String(repeating: "x", count: 1200)
        let message = AIProviderError.nonZeroExit(code: 1, stderr: long).localizedDescription
        #expect(message.count < long.count)
        #expect(message.hasSuffix("…"))
    }

    @Test
    func apiErrorTruncatesLongMessage() {
        let long = String(repeating: "y", count: 1200)
        let message = AIProviderError.apiError(status: 500, type: "server", message: long).localizedDescription
        #expect(message.count < long.count + 100)
        #expect(message.hasSuffix("…"))
    }

    @Test(arguments: [
        (PromptParserError.ioFailure(path: "/tmp/missing.txt", underlying: "no such file"), ["/tmp/missing.txt", "no such file"]),
        (.unknownVariable(name: "nonsense"),                                                ["nonsense"]),
    ] as [(PromptParserError, [String])])
    func promptParserErrorContainsExpectedFragments(error: PromptParserError, fragments: [String]) {
        let message = error.localizedDescription
        for fragment in fragments {
            #expect(message.contains(fragment), "expected '\(fragment)' in '\(message)'")
        }
    }
}
