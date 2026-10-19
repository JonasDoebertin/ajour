import Foundation
import UserNotifications
import SimpleLoginKit
@testable import Ajour

final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String?
    private let failsToLoad: Bool
    private let failsToSave: Bool
    private let failsToDelete: Bool

    init(key: String? = nil, failsToLoad: Bool = false, failsToSave: Bool = false, failsToDelete: Bool = false) {
        storedKey = key
        self.failsToLoad = failsToLoad
        self.failsToSave = failsToSave
        self.failsToDelete = failsToDelete
    }

    var key: String? {
        lock.withLock { storedKey }
    }

    func load() throws -> String? {
        if failsToLoad { throw KeychainError.status(errSecInteractionNotAllowed) }
        return key
    }

    func save(_ key: String) throws {
        if failsToSave { throw KeychainError.status(errSecInteractionNotAllowed) }
        lock.withLock { storedKey = key }
    }

    func delete() throws {
        if failsToDelete { throw KeychainError.status(errSecInteractionNotAllowed) }
        lock.withLock { storedKey = nil }
    }
}

final class InMemoryTimerStore: TimerStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecords: [TimerRecord]
    private let failsToSave: Bool

    init(records: [TimerRecord] = [], failsToSave: Bool = false) {
        storedRecords = records
        self.failsToSave = failsToSave
    }

    var records: [TimerRecord] {
        lock.withLock { storedRecords }
    }

    func load() throws -> [TimerRecord] {
        records
    }

    func save(_ records: [TimerRecord]) throws {
        if failsToSave { throw CocoaError(.fileWriteNoPermission) }
        lock.withLock { storedRecords = records }
    }
}

/// Answers each "METHOD /path" route from its own queue, so concurrent callers can't take each
/// other's responses. A held request waits until `release()`; like URLSession, it fails if its task
/// was cancelled meanwhile.
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
            if Task.isCancelled { throw URLError(.cancelled) }
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

@MainActor final class FakeLaunchAtLogin {
    var isEnabled: Bool
    var failure: (any Error)?
    private(set) var appliedSettings: [Bool] = []

    init(isEnabled: Bool = false, failure: (any Error)? = nil) {
        self.isEnabled = isEnabled
        self.failure = failure
    }

    var control: LaunchAtLoginControl {
        LaunchAtLoginControl(
            isEnabled: { self.isEnabled },
            setEnabled: { enabled in
                if let failure = self.failure { throw failure }
                self.appliedSettings.append(enabled)
                self.isEnabled = enabled
            }
        )
    }
}

struct LaunchAtLoginRefused: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

@MainActor final class FakeNotificationCenter: UserNotificationCenter {
    private(set) weak var delegate: (any UNUserNotificationCenterDelegate)?
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var authorizationRequests: [UNAuthorizationOptions] = []
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        self.delegate = delegate
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests.append(options)
        return true
    }

    func add(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedIdentifiers += identifiers
    }
}

/// Remembers that something happened, for callbacks that may run on any thread.
final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var wasSet = false

    var isSet: Bool {
        lock.withLock { wasSet }
    }

    func set() {
        lock.withLock { wasSet = true }
    }
}
