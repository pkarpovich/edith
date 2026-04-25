import Foundation

nonisolated struct PromptDefinition: Sendable, Equatable {
    let model: String?
    let effort: String?
    let body: String
}

nonisolated enum PromptParserError: Error, Sendable, Equatable {
    case ioFailure(path: String, underlying: String)
    case unknownVariable(name: String)
}

extension PromptDefinition {
    nonisolated static func parse(contents: String) -> PromptDefinition {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let stripped = stripLeadingCommentBlock(normalized)
        if let (header, body) = extractFrontmatter(stripped),
           let kv = parseFlatYAML(header) {
            return PromptDefinition(
                model: kv["model"],
                effort: kv["effort"],
                body: body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return PromptDefinition(model: nil, effort: nil, body: stripped)
    }

    nonisolated static func normalizeModel(_ input: String) -> String {
        let lower = input.lowercased()
        for keyword in ["haiku", "sonnet", "opus"] where lower.contains(keyword) {
            return keyword
        }
        return input
    }

    nonisolated static func render(definition: PromptDefinition, variables: [String: String]) throws -> String {
        var body = definition.body
        if !body.contains("{{selection}}") {
            body += "\n\n{{selection}}"
        }
        for (key, value) in variables {
            body = body.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        if let name = firstUnknownPlaceholder(in: body) {
            throw PromptParserError.unknownVariable(name: name)
        }
        return body
    }
}

nonisolated private func stripLeadingCommentBlock(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var count = 0
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            count += 1
        } else {
            break
        }
    }
    guard count >= 2 else { return text }
    return lines.dropFirst(count).joined(separator: "\n")
}

nonisolated private func extractFrontmatter(_ text: String) -> (header: String, body: String)? {
    guard text.hasPrefix("---\n") else { return nil }
    let afterOpening = String(text.dropFirst(4))
    let lines = afterOpening.split(separator: "\n", omittingEmptySubsequences: false)
    guard let close = lines.firstIndex(where: { $0 == "---" }) else { return nil }
    let header = lines[..<close].joined(separator: "\n")
    let body = lines[lines.index(after: close)...].joined(separator: "\n")
    return (header, body)
}

nonisolated private func parseFlatYAML(_ text: String) -> [String: String]? {
    var result: [String: String] = [:]
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let key = trimmed[..<colon]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        var value = trimmed[trimmed.index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)
        if value.count >= 2,
           let first = value.first,
           let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value = String(value.dropFirst().dropLast())
        }
        guard !key.isEmpty else { return nil }
        result[key] = value
    }
    return result
}

nonisolated private func firstUnknownPlaceholder(in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#) else {
        return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
          let captured = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[captured]).trimmingCharacters(in: .whitespaces)
}
