import Foundation

nonisolated enum PromptFileLoader {
    static func load(path: String) throws -> String {
        let expanded = expandTilde(path)
        do {
            return try String(contentsOfFile: expanded, encoding: .utf8)
        } catch {
            throw PromptParserError.ioFailure(path: path, underlying: error.localizedDescription)
        }
    }

    static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        return NSHomeDirectory() + String(path.dropFirst(1))
    }
}
