import Foundation

actor MockProviderRecorder {
    private(set) var calls: [(prompt: String, model: String?, effort: String?)] = []

    func record(prompt: String, model: String?, effort: String?) {
        calls.append((prompt: prompt, model: model, effort: effort))
    }
}

struct MockProvider: AIProvider {
    let delay: Duration
    let recorder: MockProviderRecorder?

    init(delay: Duration = .zero, recorder: MockProviderRecorder? = nil) {
        self.delay = delay
        self.recorder = recorder
    }

    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let delay = self.delay
        let recorder = self.recorder
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if delay > .zero {
                        try await Task.sleep(for: delay)
                    } else {
                        try Task.checkCancellation()
                    }
                    if let recorder {
                        await recorder.record(prompt: prompt, model: model, effort: effort)
                    }
                    continuation.yield(prompt.uppercased())
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
