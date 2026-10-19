import Foundation
import SimpleLoginKit

final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String?
    private let failsToLoad: Bool

    init(key: String? = nil, failsToLoad: Bool = false) {
        storedKey = key
        self.failsToLoad = failsToLoad
    }

    var key: String? {
        lock.withLock { storedKey }
    }

    func load() throws -> String? {
        if failsToLoad { throw KeychainError.status(errSecInteractionNotAllowed) }
        return key
    }

    func save(_ key: String) throws {
        lock.withLock { storedKey = key }
    }

    func delete() throws {
        lock.withLock { storedKey = nil }
    }
}

final class InMemoryTimerStore: TimerStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecords: [TimerRecord]

    init(records: [TimerRecord] = []) {
        storedRecords = records
    }

    var records: [TimerRecord] {
        lock.withLock { storedRecords }
    }

    func load() throws -> [TimerRecord] {
        records
    }

    func save(_ records: [TimerRecord]) throws {
        lock.withLock { storedRecords = records }
    }
}

final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(status: Int, data: Data)] = []
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func enqueue(status: Int = 200, json: String) {
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

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}
