import Foundation
import os

nonisolated struct AnthropicSSEParser: Sendable {
    enum Event: Equatable, Sendable {
        case textDelta(String)
        case messageStop
        case error(type: String, message: String)
    }

    private var bytes: [UInt8] = []

    mutating func feed(_ data: Data) -> [Event] {
        bytes.append(contentsOf: data)
        return drain()
    }

    mutating func feed(_ string: String) -> [Event] {
        return feed(Data(string.utf8))
    }

    private mutating func drain() -> [Event] {
        var events: [Event] = []
        while let raw = takeNextEvent() {
            if let parsed = AnthropicSSEParser.interpret(rawEvent: raw) {
                events.append(parsed)
            }
        }
        return events
    }

    private mutating func takeNextEvent() -> String? {
        guard let separatorIndex = findDoubleNewlineIndex() else { return nil }
        let eventBytes = Array(bytes[0..<separatorIndex])
        bytes.removeSubrange(0..<(separatorIndex + 2))
        return String(decoding: eventBytes, as: UTF8.self)
    }

    private func findDoubleNewlineIndex() -> Int? {
        guard bytes.count >= 2 else { return nil }
        for i in 0..<(bytes.count - 1) where bytes[i] == 0x0A && bytes[i + 1] == 0x0A {
            return i
        }
        return nil
    }

    static func interpret(rawEvent: String) -> Event? {
        var eventName: String?
        var dataLines: [String] = []
        for line in rawEvent.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineString = String(line)
            if lineString.hasPrefix(":") { continue }
            if let value = field(prefix: "event:", line: lineString) {
                eventName = value
            } else if let value = field(prefix: "data:", line: lineString) {
                dataLines.append(value)
            }
        }
        guard let name = eventName else { return nil }
        let payload = dataLines.joined(separator: "\n")
        switch name {
        case "content_block_delta":
            return parseContentBlockDelta(payload)
        case "message_stop":
            return .messageStop
        case "error":
            return parseError(payload)
        default:
            return nil
        }
    }

    private static func field(prefix: String, line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let raw = String(line.dropFirst(prefix.count))
        if raw.hasPrefix(" ") {
            return String(raw.dropFirst())
        }
        return raw
    }

    private static func parseContentBlockDelta(_ payload: String) -> Event? {
        guard let json = decodeJSON(payload) else { return nil }
        guard let delta = json["delta"] as? [String: Any],
              let type = delta["type"] as? String else {
            return nil
        }
        guard type == "text_delta",
              let text = delta["text"] as? String else {
            return nil
        }
        return .textDelta(text)
    }

    private static func parseError(_ payload: String) -> Event? {
        guard let json = decodeJSON(payload) else { return nil }
        guard let err = json["error"] as? [String: Any],
              let type = err["type"] as? String,
              let message = err["message"] as? String else {
            return nil
        }
        return .error(type: type, message: message)
    }

    private static func decodeJSON(_ payload: String) -> [String: Any]? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            return nil
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            return object as? [String: Any]
        } catch {
            Logger.edith.warning("AnthropicSSEParser: malformed JSON payload (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }
}
