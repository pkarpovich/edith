import Foundation
import Testing
@testable import edith

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var chunks: [String] = []
    for try await chunk in stream {
        chunks.append(chunk)
    }
    return chunks
}

private func collectJoined(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
    try await collect(stream).joined()
}

struct MockProviderTests {
    @Test
    func returnsUppercasedPromptWithoutDelay() async throws {
        let provider = MockProvider()
        let output = try await collectJoined(provider.run(prompt: "hello edith", model: nil, effort: nil))
        #expect(output == "HELLO EDITH")
    }

    @Test
    func emptyPromptReturnsEmpty() async throws {
        let provider = MockProvider()
        let output = try await collectJoined(provider.run(prompt: "", model: nil, effort: nil))
        #expect(output == "")
    }

    @Test
    func returnsUppercasedPromptIgnoringModelAndEffort() async throws {
        let provider = MockProvider()
        let a = try await collectJoined(provider.run(prompt: "go", model: "haiku", effort: "low"))
        let b = try await collectJoined(provider.run(prompt: "go", model: "opus", effort: "high"))
        #expect(a == b)
        #expect(a == "GO")
    }

    @Test
    func yieldsExactlyOneChunk() async throws {
        let provider = MockProvider()
        let chunks = try await collect(provider.run(prompt: "hello", model: nil, effort: nil))
        #expect(chunks.count == 1)
        #expect(chunks.first == "HELLO")
    }

    @Test
    func honorsInjectedDelay() async throws {
        let delay: Duration = .milliseconds(100)
        let provider = MockProvider(delay: delay)
        let start = ContinuousClock.now
        let output = try await collectJoined(provider.run(prompt: "go", model: nil, effort: nil))
        let elapsed = ContinuousClock.now - start
        #expect(output == "GO")
        #expect(elapsed >= delay)
    }

    @Test
    func cancellationDuringDelayInterruptsBeforeFullDuration() async throws {
        let provider = MockProvider(delay: .seconds(5))
        let start = ContinuousClock.now
        let task = Task<String, Error> {
            try await collectJoined(provider.run(prompt: "go", model: nil, effort: nil))
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        _ = try? await task.value
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(1))
    }

    @Test
    func recorderCapturesPromptModelAndEffort() async throws {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(recorder: recorder)
        _ = try await collectJoined(provider.run(prompt: "fix it", model: "haiku", effort: "low"))

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.prompt == "fix it")
        #expect(calls.first?.model == "haiku")
        #expect(calls.first?.effort == "low")
    }

    @Test
    func recorderCapturesNilModelAndEffort() async throws {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(recorder: recorder)
        _ = try await collectJoined(provider.run(prompt: "do it", model: nil, effort: nil))

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.model == nil)
        #expect(calls.first?.effort == nil)
    }

    @Test
    func recorderCapturesMultipleCallsInOrder() async throws {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(recorder: recorder)
        _ = try await collectJoined(provider.run(prompt: "first", model: "haiku", effort: nil))
        _ = try await collectJoined(provider.run(prompt: "second", model: "sonnet", effort: "medium"))
        _ = try await collectJoined(provider.run(prompt: "third", model: nil, effort: "high"))

        let calls = await recorder.calls
        #expect(calls.count == 3)
        #expect(calls[0].prompt == "first")
        #expect(calls[0].model == "haiku")
        #expect(calls[1].prompt == "second")
        #expect(calls[1].effort == "medium")
        #expect(calls[2].prompt == "third")
        #expect(calls[2].effort == "high")
    }
}
