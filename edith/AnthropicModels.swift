import Foundation

nonisolated enum AnthropicModels {
    static let aliases: [String: String] = [
        "haiku": "claude-haiku-4-5",
        "sonnet": "claude-sonnet-4-6",
        "opus": "claude-opus-4-7",
    ]

    static let defaultModel = "claude-sonnet-4-6"

    static func resolve(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return defaultModel }
        if let resolved = aliases[model.lowercased()] {
            return resolved
        }
        return model
    }
}
