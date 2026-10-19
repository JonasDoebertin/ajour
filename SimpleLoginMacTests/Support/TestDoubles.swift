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

/// Answers each "METHOD /path" route from its own queue, so concurrent callers can't take each
/// other's responses. A held request waits until `release()`.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private struct Response {
        let status: Int
        let data: Data
    }

    private let lock = NSLock()
    private var responses: [String: [Response]] = [:]
    private var recordedRequests: [URLRequest] = []
    private var pendingHolds: [String: Response] = [:]
    private var heldRequests: [CheckedContinuation<Void, Never>] = []
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func enqueue(_ path: String, method: String = "GET", status: Int = 200, json: String) {
        lock.withLock { responses[Self.route(method, path), default: []].append(Response(status: status, data: Data(json.utf8))) }
    }

    /// The next request to the route waits until `release()` and then gets this response.
    func holdNext(_ path: String, method: String = "GET", status: Int = 200, json: String) {
        lock.withLock { pendingHolds[Self.route(method, path)] = Response(status: status, data: Data(json.utf8)) }
    }

    func waitUntilARequestIsHeld() async {
        await withCheckedContinuation { continuation in
            let isHeld = lock.withLock {
                if heldRequests.isEmpty { heldWaiters.append(continuation) }
                return !heldRequests.isEmpty
            }
            if isHeld { continuation.resume() }
        }
    }

    func release() {
        let held = lock.withLock {
            defer { heldRequests = [] }
            return heldRequests
        }
        held.forEach { $0.resume() }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let route = Self.route(request.httpMethod ?? "GET", request.url!.path)
        let heldResponse: Response? = lock.withLock {
            recordedRequests.append(request)
            return pendingHolds.removeValue(forKey: route)
        }
        if heldResponse != nil {
            await withCheckedContinuation { continuation in
                let waiters = lock.withLock {
                    heldRequests.append(continuation)
                    defer { heldWaiters = [] }
                    return heldWaiters
                }
                waiters.forEach { $0.resume() }
            }
        }
        let next: Response? = heldResponse ?? lock.withLock {
            responses[route]?.isEmpty == false ? responses[route]?.removeFirst() : nil
        }
        guard let next else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        return (next.data, response)
    }

    private static func route(_ method: String, _ path: String) -> String {
        "\(method) \(path)"
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
