import Foundation
import Testing
@testable import edith

struct AnthropicModelsTests {
    @Test
    func haikuAliasResolves() {
        #expect(AnthropicModels.resolve("haiku") == "claude-haiku-4-5")
    }

    @Test
    func sonnetAliasResolves() {
        #expect(AnthropicModels.resolve("sonnet") == "claude-sonnet-4-6")
    }

    @Test
    func opusAliasResolves() {
        #expect(AnthropicModels.resolve("opus") == "claude-opus-4-7")
    }

    @Test
    func datedModelPassesThrough() {
        #expect(AnthropicModels.resolve("claude-haiku-4-5-20251001") == "claude-haiku-4-5-20251001")
    }

    @Test
    func unknownModelPassesThrough() {
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

    @Test
    func aliasIsCaseInsensitive() {
        #expect(AnthropicModels.resolve("Haiku") == "claude-haiku-4-5")
        #expect(AnthropicModels.resolve("OPUS") == "claude-opus-4-7")
    }
}
