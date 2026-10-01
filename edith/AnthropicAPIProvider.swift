import Foundation

struct AnthropicAPIProvider: AIProvider {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"
    static let defaultMaxTokens = 64000
    static let errorBodyLimit = 4096

    static var outputFormat: [String: Any] {
        [
            "type": "json_schema",
            "schema": [
                "type": "object",
                "properties": ["text": ["type": "string"]],
                "required": ["text"],
                "additionalProperties": false,
            ],
        ]
    }

    let transport: any AnthropicTransport
    let apiKeyProvider: @Sendable () -> String?
    let cacheablePrefix: String

    nonisolated init(
        transport: any AnthropicTransport,
        apiKeyProvider: @Sendable @escaping () -> String? = AnthropicAPIProvider.defaultAPIKeyProvider(),
        cacheablePrefix: String = ""
    ) {
        self.transport = transport
        self.apiKeyProvider = apiKeyProvider
        self.cacheablePrefix = cacheablePrefix
    }

    nonisolated static func defaultAPIKeyProvider(
        keychain: KeychainStore = KeychainStore(),
        environment: @Sendable @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) -> @Sendable () -> String? {
        return {
            if let key = keychain.read(), !key.isEmpty {
                return key
            }
            return environment()["ANTHROPIC_API_KEY"]
        }
    }

    func run(prompt: String, model: String?, effort: String?) -> AsyncThrowingStream<ProviderEvent, Error> {
        let transport = self.transport
        let apiKeyProvider = self.apiKeyProvider
        let cacheablePrefix = self.cacheablePrefix
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
                        throw AIProviderError.missingApiKey
                    }
                    let request = try Self.buildRequest(
                        apiKey: apiKey,
                        prompt: prompt,
                        model: model,
                        effort: effort,
                        cacheablePrefix: cacheablePrefix
                    )
                    let (http, dataStream) = try await transport.openStream(request: request)
                    if !(200..<300).contains(http.statusCode) {
                        let bodyText = try await Self.drainBody(dataStream, limit: Self.errorBodyLimit)
                        let (errType, errMessage) = Self.parseErrorBody(bodyText, status: http.statusCode)
                        throw AIProviderError.apiError(status: http.statusCode, type: errType, message: errMessage)
                    }
                    var parser = AnthropicSSEParser()
                    var output = ""
                    var stopReason: String?
                    var refusalCategory: String?
                    for try await chunk in dataStream {
                        try Task.checkCancellation()
                        for event in parser.feed(chunk) {
                            switch event {
                            case .textDelta(let text):
                                output += text
                            case .messageDelta(let reason, let category):
                                stopReason = reason ?? stopReason
                                refusalCategory = category ?? refusalCategory
                            case .messageStop:
                                let response = try Self.parseResponse(
                                    output,
                                    stopReason: stopReason,
                                    refusalCategory: refusalCategory
                                )
                                continuation.yield(.finished(response))
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

    static func buildRequest(
        apiKey: String,
        prompt: String,
        model: String?,
        effort: String?,
        cacheablePrefix: String = ""
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        var outputConfig: [String: Any] = ["format": outputFormat]
        if let effort, !effort.isEmpty {
            outputConfig["effort"] = effort
        }
        let body: [String: Any] = [
            "model": AnthropicModels.resolve(model),
            "max_tokens": defaultMaxTokens,
            "stream": true,
            "output_config": outputConfig,
            "messages": [
                ["role": "user", "content": userContent(prompt: prompt, cacheablePrefix: cacheablePrefix)],
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

    static func userContent(prompt: String, cacheablePrefix: String) -> Any {
        guard !cacheablePrefix.isEmpty, prompt.hasPrefix(cacheablePrefix), prompt.count > cacheablePrefix.count else {
            return prompt
        }
        let variablePart = String(prompt.dropFirst(cacheablePrefix.count))
        return [
            ["type": "text", "text": cacheablePrefix, "cache_control": ["type": "ephemeral"]],
            ["type": "text", "text": variablePart],
        ]
    }

    static func parseResponse(_ output: String, stopReason: String?, refusalCategory: String?) throws -> ProviderResponse {
        if stopReason == "refusal" {
            throw AIProviderError.refusal(category: refusalCategory)
        }
        if stopReason == "max_tokens" {
            throw AIProviderError.maxTokens(rawOutput: output)
        }
        if stopReason == "model_context_window_exceeded" {
            throw AIProviderError.contextWindowExceeded(rawOutput: output)
        }
        if output.isEmpty {
            throw AIProviderError.emptyOutput(stopReason: stopReason)
        }
        guard let reply = try? JSONDecoder().decode(StructuredReply.self, from: Data(output.utf8)),
              !reply.text.isEmpty else {
            throw AIProviderError.malformedOutput(rawOutput: output, stopReason: stopReason)
        }
        return ProviderResponse(text: reply.text, rawOutput: output, stopReason: stopReason)
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

nonisolated private struct StructuredReply: Decodable {
    let text: String
}
