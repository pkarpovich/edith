import Foundation

struct MockProvider: AIProvider {
    let delay: Duration

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func run(prompt: String, input: String) async throws -> String {
        if delay > .zero {
            try await Task.sleep(for: delay)
        } else {
            try Task.checkCancellation()
        }
        return input.uppercased()
    }
}
