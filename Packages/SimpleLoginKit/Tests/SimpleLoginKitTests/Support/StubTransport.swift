import Foundation
import SimpleLoginKit

final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(status: Int, data: Data)] = []
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func enqueue(status: Int, json: String) {
        lock.withLock { responses.append((status, Data(json.utf8))) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: (status: Int, data: Data)? = lock.withLock {
            recordedRequests.append(request)
            return responses.isEmpty ? nil : responses.removeFirst()
        }
        guard let next else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (next.data, response)
    }
}
