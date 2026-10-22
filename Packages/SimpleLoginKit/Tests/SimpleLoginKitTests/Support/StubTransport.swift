import Foundation
import SimpleLoginKit

final class StubTransport: HTTPTransport, @unchecked Sendable {
    private enum Outcome {
        case response(status: Int, data: Data)
        case failure(URLError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome] = []
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func enqueue(status: Int, json: String) {
        lock.withLock { outcomes.append(.response(status: status, data: Data(json.utf8))) }
    }

    func enqueue(error: URLError) {
        lock.withLock { outcomes.append(.failure(error)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: Outcome? = lock.withLock {
            recordedRequests.append(request)
            return outcomes.isEmpty ? nil : outcomes.removeFirst()
        }
        switch next {
        case .response(let status, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        case .failure(let error):
            throw error
        case nil:
            throw URLError(.notConnectedToInternet)
        }
    }
}
