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

    func run(prompt: String, model: String?, effort: String?) async throws -> String {
        if delay > .zero {
            try await Task.sleep(for: delay)
        } else {
            try Task.checkCancellation()
        }
        if let recorder {
            await recorder.record(prompt: prompt, model: model, effort: effort)
        }
        return prompt.uppercased()
    }
}
