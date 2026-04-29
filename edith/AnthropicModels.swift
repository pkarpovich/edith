import Foundation

nonisolated enum AnthropicModels {
    static let defaultModel = "claude-sonnet-4-6"

    static func resolve(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return defaultModel }
        return model
    }
}
