import Foundation
import Testing
@testable import edith

private struct FakeTransport: AnthropicTransport {
    let statusCode: Int
    let chunks: [Data]

    init(statusCode: Int = 200, chunks: [Data]) {
        self.statusCode = statusCode
        self.chunks = chunks
    }

    func openStream(request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let response = HTTPURLResponse(
            url: request.url ?? AnthropicAPIProvider.endpoint,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        let chunks = self.chunks
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        return (response, stream)
    }
}

private struct FailingTransport: AnthropicTransport {
    let error: Error

    func openStream(request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        throw error
    }
}

private func sseEvent(_ name: String, data: String) -> String {
    return "event: \(name)\ndata: \(data)\n\n"
}

private func textDeltaEvent(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
    let payload = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(escaped)"}}"#
    return sseEvent("content_block_delta", data: payload)
}

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var out: [String] = []
    for try await chunk in stream {
        out.append(chunk)
    }
    return out
}

struct AnthropicAPIProviderTests {
    @Test
    func happyPathYieldsTextDeltasInOrder() async throws {
        let body = textDeltaEvent("foo") + textDeltaEvent("bar") + sseEvent("message_stop", data: #"{"type":"message_stop"}"#)
        let transport = FakeTransport(chunks: [Data(body.utf8)])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "test-key" })

        let chunks = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
        #expect(chunks == ["foo", "bar"])
    }

    @Test
    func missingApiKeyThrows() async {
        let transport = FakeTransport(chunks: [])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { nil })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected missingApiKey error")
        } catch let error as AIProviderError {
            #expect(error == .missingApiKey)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func emptyApiKeyThrowsMissingApiKey() async {
        let transport = FakeTransport(chunks: [])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected missingApiKey error")
        } catch let error as AIProviderError {
            #expect(error == .missingApiKey)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func http401MapsToApiError() async {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let transport = FakeTransport(statusCode: 401, chunks: [Data(body.utf8)])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "bad" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected apiError")
        } catch let error as AIProviderError {
            switch error {
            case .apiError(let status, let type, let message):
                #expect(status == 401)
                #expect(type == "authentication_error")
                #expect(message == "invalid x-api-key")
            default:
                Issue.record("unexpected provider error: \(error)")
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func http429MapsToApiError() async {
        let body = #"{"type":"error","error":{"type":"rate_limit_error","message":"too many requests"}}"#
        let transport = FakeTransport(statusCode: 429, chunks: [Data(body.utf8)])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "key" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected apiError")
        } catch let error as AIProviderError {
            switch error {
            case .apiError(let status, let type, _):
                #expect(status == 429)
                #expect(type == "rate_limit_error")
            default:
                Issue.record("unexpected provider error: \(error)")
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func http500WithUnparseableBodyFallsBackToHttpStatusType() async {
        let transport = FakeTransport(statusCode: 500, chunks: [Data("internal".utf8)])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "key" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected apiError")
        } catch let error as AIProviderError {
            switch error {
            case .apiError(let status, let type, let message):
                #expect(status == 500)
                #expect(type == "http_500")
                #expect(message == "internal")
            default:
                Issue.record("unexpected provider error: \(error)")
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func serverSentErrorEventThrowsApiError() async {
        let errorPayload = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        let body = textDeltaEvent("partial") + sseEvent("error", data: errorPayload)
        let transport = FakeTransport(chunks: [Data(body.utf8)])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "key" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected apiError")
        } catch let error as AIProviderError {
            switch error {
            case .apiError(let status, let type, let message):
                #expect(status == 0)
                #expect(type == "overloaded_error")
                #expect(message == "Overloaded")
            default:
                Issue.record("unexpected provider error: \(error)")
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func messageStopWithoutTextDeltasThrowsEmptyOutput() async {
        let body = sseEvent("message_stop", data: #"{"type":"message_stop"}"#)
        let transport = FakeTransport(chunks: [Data(body.utf8)])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "key" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected emptyOutput error")
        } catch let error as AIProviderError {
            #expect(error == .emptyOutput)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func transportErrorPropagates() async {
        struct BoomError: Error, Equatable {}
        let provider = AnthropicAPIProvider(transport: FailingTransport(error: BoomError()), apiKeyProvider: { "key" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected error")
        } catch is BoomError {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func chunksSplitMidEventStillProduceDeltas() async throws {
        let full = textDeltaEvent("hello") + sseEvent("message_stop", data: #"{"type":"message_stop"}"#)
        let bytes = Array(full.utf8)
        let cut = bytes.count / 2
        let first = Data(bytes[0..<cut])
        let second = Data(bytes[cut...])
        let transport = FakeTransport(chunks: [first, second])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "key" })

        let chunks = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
        #expect(chunks == ["hello"])
    }

    @Test
    func streamWithoutMessageStopThrowsTruncatedStream() async {
        let body = textDeltaEvent("partial")
        let transport = FakeTransport(chunks: [Data(body.utf8)])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "key" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected truncatedStream error")
        } catch let error as AIProviderError {
            #expect(error == .truncatedStream)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func emptyStreamThrowsTruncatedStream() async {
        let transport = FakeTransport(chunks: [])
        let provider = AnthropicAPIProvider(transport: transport, apiKeyProvider: { "key" })

        do {
            _ = try await collect(provider.run(prompt: "hi", model: nil, effort: nil))
            Issue.record("expected truncatedStream error")
        } catch let error as AIProviderError {
            #expect(error == .truncatedStream)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func buildRequestSetsHeadersAndBody() throws {
        let request = try AnthropicAPIProvider.buildRequest(apiKey: "secret", prompt: "hi", model: "haiku")

        #expect(request.url == AnthropicAPIProvider.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "accept") == "text/event-stream")

        let bodyData = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let json = try #require(object)
        #expect(json["model"] as? String == "claude-haiku-4-5")
        #expect(json["max_tokens"] as? Int == AnthropicAPIProvider.defaultMaxTokens)
        #expect(json["stream"] as? Bool == true)
        let messages = json["messages"] as? [[String: String]]
        #expect(messages == [["role": "user", "content": "hi"]])
    }

    @Test
    func buildRequestUsesDefaultModelWhenNil() throws {
        let request = try AnthropicAPIProvider.buildRequest(apiKey: "k", prompt: "p", model: nil)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["model"] as? String == AnthropicModels.defaultModel)
    }
}
