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
        return PromptDefinition(
            model: nil,
            effort: nil,
            body: stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
        if let name = firstUnknownPlaceholder(in: body, knownNames: Set(variables.keys)) {
            throw PromptParserError.unknownVariable(name: name)
        }
        for (key, value) in variables {
            body = body.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return body
    }
}

nonisolated private func stripLeadingCommentBlock(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var commentCount = 0
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            commentCount += 1
        } else {
            break
        }
    }
    guard commentCount >= 2 else { return text }
    var dropTotal = commentCount
    while dropTotal < lines.count,
          lines[dropTotal].trimmingCharacters(in: .whitespaces).isEmpty {
        dropTotal += 1
    }
    return lines.dropFirst(dropTotal).joined(separator: "\n")
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

nonisolated private func firstUnknownPlaceholder(in text: String, knownNames: Set<String>) -> String? {
    let regex = try! NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: range)
    for match in matches {
        guard match.numberOfRanges >= 2,
              let captured = Range(match.range(at: 1), in: text) else { continue }
        let name = String(text[captured])
        if !knownNames.contains(name) {
            return name
        }
    }
    return nil
}
