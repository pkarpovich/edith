import Foundation
import Testing
@testable import edith

struct AnthropicModelsTests {
    @Test(arguments: [
        ("claude-haiku-4-5-20251001", "claude-haiku-4-5-20251001"),
        ("custom-model-x", "custom-model-x"),
        (nil, "claude-sonnet-4-6"),
        ("", "claude-sonnet-4-6"),
    ] as [(String?, String)])
    func resolveProducesExpectedModel(input: String?, expected: String) {
        #expect(AnthropicModels.resolve(input) == expected)
    }
}
