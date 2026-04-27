import Foundation

protocol AnthropicTransport: Sendable {
    func openStream(request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
}

struct URLSessionAnthropicTransport: AnthropicTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func openStream(request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw AIProviderError.apiError(status: 0, type: "invalid_response", message: "Non-HTTP response")
        }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 0x0A {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                bytes.task.cancel()
            }
        }
        return (http, stream)
    }
}
