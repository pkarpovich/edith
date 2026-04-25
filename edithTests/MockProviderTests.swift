import Foundation
import Testing
@testable import edith

struct MockProviderTests {
    @Test
    func returnsUppercasedPromptWithoutDelay() async throws {
        let provider = MockProvider()
        let output = try await provider.run(prompt: "hello edith", model: nil, effort: nil)
        #expect(output == "HELLO EDITH")
    }

    @Test
    func emptyPromptReturnsEmpty() async throws {
        let provider = MockProvider()
        let output = try await provider.run(prompt: "", model: nil, effort: nil)
        #expect(output == "")
    }

    @Test
    func returnsUppercasedPromptIgnoringModelAndEffort() async throws {
        let provider = MockProvider()
        let a = try await provider.run(prompt: "go", model: "haiku", effort: "low")
        let b = try await provider.run(prompt: "go", model: "opus", effort: "high")
        #expect(a == b)
        #expect(a == "GO")
    }

    @Test
    func honorsInjectedDelay() async throws {
        let delay: Duration = .milliseconds(100)
        let provider = MockProvider(delay: delay)
        let start = ContinuousClock.now
        let output = try await provider.run(prompt: "go", model: nil, effort: nil)
        let elapsed = ContinuousClock.now - start
        #expect(output == "GO")
        #expect(elapsed >= delay)
    }

    @Test
    func cancellationDuringDelayThrowsCancellationError() async throws {
        let provider = MockProvider(delay: .seconds(5))
        let task = Task<String, Error> {
            try await provider.run(prompt: "go", model: nil, effort: nil)
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test
    func recorderCapturesPromptModelAndEffort() async throws {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(recorder: recorder)
        _ = try await provider.run(prompt: "fix it", model: "haiku", effort: "low")

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
        _ = try await provider.run(prompt: "do it", model: nil, effort: nil)

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.model == nil)
        #expect(calls.first?.effort == nil)
    }

    @Test
    func recorderCapturesMultipleCallsInOrder() async throws {
        let recorder = MockProviderRecorder()
        let provider = MockProvider(recorder: recorder)
        _ = try await provider.run(prompt: "first", model: "haiku", effort: nil)
        _ = try await provider.run(prompt: "second", model: "sonnet", effort: "medium")
        _ = try await provider.run(prompt: "third", model: nil, effort: "high")

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
