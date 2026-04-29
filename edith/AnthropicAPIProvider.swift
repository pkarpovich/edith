import Foundation
import os

struct AnthropicAPIProvider: AIProvider {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"
    static let defaultMaxTokens = 4096
    static let errorBodyLimit = 4096

    private static let effortWarningLogged = OSAllocatedUnfairLock<Bool>(initialState: false)

    let transport: any AnthropicTransport
    let apiKeyProvider: @Sendable () -> String?

    init(
        transport: any AnthropicTransport,
        apiKeyProvider: @Sendable @escaping () -> String? = {
            ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        }
    ) {
        self.transport = transport
        self.apiKeyProvider = apiKeyProvider
    }

    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<String, Error> {
        let transport = self.transport
        let apiKeyProvider = self.apiKeyProvider
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let effort, !effort.isEmpty {
                        Self.warnEffortIgnoredOnce()
                    }
                    guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
                        throw AIProviderError.missingApiKey
                    }
                    let request = try Self.buildRequest(apiKey: apiKey, prompt: prompt, model: model)
                    let (http, dataStream) = try await transport.openStream(request: request)
                    if !(200..<300).contains(http.statusCode) {
                        let bodyText = try await Self.drainBody(dataStream, limit: Self.errorBodyLimit)
                        let (errType, errMessage) = Self.parseErrorBody(bodyText, status: http.statusCode)
                        throw AIProviderError.apiError(status: http.statusCode, type: errType, message: errMessage)
                    }
                    var parser = AnthropicSSEParser()
                    var sawTextDelta = false
                    for try await chunk in dataStream {
                        try Task.checkCancellation()
                        for event in parser.feed(chunk) {
                            switch event {
                            case .textDelta(let text):
                                sawTextDelta = true
                                continuation.yield(text)
                            case .messageStop:
                                if !sawTextDelta {
                                    throw AIProviderError.emptyOutput
                                }
                                continuation.finish()
                                return
                            case .error(let type, let message):
                                throw AIProviderError.apiError(status: 0, type: type, message: message)
                            }
                        }
                    }
                    throw AIProviderError.truncatedStream
                } catch is CancellationError {
                    continuation.finish(throwing: AIProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    static func buildRequest(apiKey: String, prompt: String, model: String?) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        let body: [String: Any] = [
            "model": AnthropicModels.resolve(model),
            "max_tokens": defaultMaxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    static func drainBody(_ stream: AsyncThrowingStream<Data, Error>, limit: Int) async throws -> String {
        var data = Data()
        for try await chunk in stream {
            let remaining = limit - data.count
            if remaining <= 0 { break }
            if chunk.count < remaining {
                data.append(chunk)
            } else {
                data.append(chunk.prefix(remaining))
                break
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func warnEffortIgnoredOnce() {
        let shouldLog = effortWarningLogged.withLock { logged in
            guard !logged else { return false }
            logged = true
            return true
        }
        if shouldLog {
            Logger.edith.warning("AnthropicAPIProvider: 'effort' is ignored for the API provider in this phase")
        }
    }

    static func parseErrorBody(_ body: String, status: Int) -> (type: String, message: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let payload = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let err = object["error"] as? [String: Any],
           let type = err["type"] as? String,
           let message = err["message"] as? String {
            return (type, message)
        }
        let fallbackType = "http_\(status)"
        let fallbackMessage = trimmed.isEmpty ? "HTTP \(status)" : trimmed
        return (fallbackType, fallbackMessage)
    }
}
