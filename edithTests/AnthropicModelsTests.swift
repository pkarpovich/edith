import Foundation
import Testing
@testable import edith

struct AnthropicModelsTests {
    @Test
    func datedModelPassesThrough() {
        #expect(AnthropicModels.resolve("claude-haiku-4-5-20251001") == "claude-haiku-4-5-20251001")
    }

    @Test
    func arbitraryStringPassesThrough() {
        #expect(AnthropicModels.resolve("custom-model-x") == "custom-model-x")
    }

    @Test
    func nilUsesDefault() {
        #expect(AnthropicModels.resolve(nil) == "claude-sonnet-4-6")
    }

    @Test
    func emptyStringUsesDefault() {
        #expect(AnthropicModels.resolve("") == "claude-sonnet-4-6")
    }
}
