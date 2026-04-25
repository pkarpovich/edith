import Foundation
import Testing
@testable import edith

struct MockProviderTests {
    @Test
    func returnsUppercasedInputWithoutDelay() async throws {
        let provider = MockProvider()
        let output = try await provider.run(prompt: "any prompt", input: "hello edith")
        #expect(output == "HELLO EDITH")
    }

    @Test
    func emptyInputReturnsEmpty() async throws {
        let provider = MockProvider()
        let output = try await provider.run(prompt: "", input: "")
        #expect(output == "")
    }

    @Test
    func ignoresPromptValue() async throws {
        let provider = MockProvider()
        let a = try await provider.run(prompt: "translate to russian", input: "hi")
        let b = try await provider.run(prompt: "make it shorter", input: "hi")
        #expect(a == b)
        #expect(a == "HI")
    }

    @Test
    func honorsInjectedDelay() async throws {
        let delay: Duration = .milliseconds(100)
        let provider = MockProvider(delay: delay)
        let start = ContinuousClock.now
        let output = try await provider.run(prompt: "p", input: "go")
        let elapsed = ContinuousClock.now - start
        #expect(output == "GO")
        #expect(elapsed >= delay)
    }

    @Test
    func cancellationDuringDelayThrowsCancellationError() async throws {
        let provider = MockProvider(delay: .seconds(5))
        let task = Task<String, Error> {
            try await provider.run(prompt: "p", input: "go")
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test
    func cancellationBeforeRunWithoutDelayThrowsCancellationError() async throws {
        let provider = MockProvider()
        let task = Task<String, Error> {
            try await Task.sleep(for: .milliseconds(50))
            return try await provider.run(prompt: "p", input: "go")
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
