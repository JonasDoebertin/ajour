import Foundation
import Testing
@testable import SimpleLoginKit

@Suite struct SimpleLoginAPITests {
    @Test func userInfoSendsAuthHeaderAndDecodes() async throws {
        let stub = StubTransport()
        stub.enqueue(status: 200, json: #"{"name":"Jonas","email":"j@example.com","is_premium":true,"in_trial":false,"max_alias_free_plan":5}"#)
        let api = SimpleLoginAPI(apiKey: "secret", transport: stub)
        let info = try await api.userInfo()
        #expect(info == UserInfo(name: "Jonas", email: "j@example.com", isPremium: true))
        #expect(stub.requests[0].url?.absoluteString == "https://app.simplelogin.io/api/user_info")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authentication") == "secret")
    }

    @Test func anAliasIsAlwaysReadFromTheServerInsteadOfACache() async throws {
        let stub = StubTransport()
        stub.enqueue(status: 200, json: Fixtures.aliasJSON)
        _ = try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: .once).alias(id: 7)
        #expect(stub.requests[0].cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func status401MapsToUnauthorized() async {
        let stub = StubTransport(); stub.enqueue(status: 401, json: #"{"error":"Wrong api key"}"#)
        await #expect(throws: APIError.unauthorized) { try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: .once).userInfo() }
    }

    @Test func errorBodyIsSurfaced() async {
        let stub = StubTransport(); stub.enqueue(status: 400, json: #"{"error":"Alias quota exceeded"}"#)
        await #expect(throws: APIError.server(status: 400, message: "Alias quota exceeded")) { try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: .once).userInfo() }
    }

    @Test func transportFailureMapsToTransportError() async {
        let stub = StubTransport() // empty queue throws URLError
        await #expect { try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: .once).userInfo() } throws: { error in
            if case APIError.transport = error { return true } else { return false }
        }
    }

    // MARK: Retries

    private static let quick = RetryPolicy(attempts: 3, delay: .zero)
    private static let userInfoJSON = #"{"name":"Jonas","email":"j@example.com","is_premium":true,"in_trial":false,"max_alias_free_plan":5}"#
    private static let toggleJSON = #"{"enabled":true}"#

    @Test func aTransientFailureIsRetriedUntilItSucceeds() async throws {
        let stub = StubTransport()
        stub.enqueue(error: URLError(.timedOut))
        stub.enqueue(status: 503, json: #"{"error":"Busy"}"#)
        stub.enqueue(status: 200, json: Self.userInfoJSON)
        _ = try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).userInfo()
        #expect(stub.requests.count == 3)
    }

    @Test func aRequestIsTriedAtMostThreeTimes() async {
        let stub = StubTransport()
        for _ in 0..<4 { stub.enqueue(status: 503, json: #"{"error":"Busy"}"#) }
        await #expect(throws: APIError.server(status: 503, message: "Busy")) {
            try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).userInfo()
        }
        #expect(stub.requests.count == 3)
    }

    @Test(arguments: [400, 401, 403, 404])
    func rejectionsAreNotRetried(status: Int) async {
        let stub = StubTransport()
        for _ in 0..<3 { stub.enqueue(status: status, json: #"{"error":"No"}"#) }
        await #expect(throws: APIError.self) {
            try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).userInfo()
        }
        #expect(stub.requests.count == 1)
    }

    @Test func rateLimitingIsRetried() async throws {
        let stub = StubTransport()
        stub.enqueue(status: 429, json: #"{"error":"Slow down"}"#)
        stub.enqueue(status: 200, json: Self.userInfoJSON)
        _ = try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).userInfo()
        #expect(stub.requests.count == 2)
    }

    @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost])
    func aToggleIsNotRepeatedAfterItMayHaveArrived(code: URLError.Code) async {
        let stub = StubTransport()
        stub.enqueue(error: URLError(code))
        stub.enqueue(status: 200, json: Self.toggleJSON)
        await #expect(throws: APIError.self) {
            try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).toggle(aliasID: 1)
        }
        #expect(stub.requests.count == 1)
    }

    @Test func aToggleAnsweredWithAServerErrorIsNotRepeated() async {
        let stub = StubTransport()
        stub.enqueue(status: 502, json: #"{"error":"Bad gateway"}"#)
        stub.enqueue(status: 200, json: Self.toggleJSON)
        await #expect(throws: APIError.server(status: 502, message: "Bad gateway")) {
            try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).toggle(aliasID: 1)
        }
        #expect(stub.requests.count == 1)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed])
    func aToggleThatNeverLeftIsRetried(code: URLError.Code) async throws {
        let stub = StubTransport()
        stub.enqueue(error: URLError(code))
        stub.enqueue(status: 200, json: Self.toggleJSON)
        let enabled = try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).toggle(aliasID: 1)
        #expect(enabled)
        #expect(stub.requests.count == 2)
    }

    @Test func aNewRandomAliasIsNotRepeatedAfterATimeout() async {
        let stub = StubTransport()
        stub.enqueue(error: URLError(.timedOut))
        await #expect(throws: APIError.self) {
            try await SimpleLoginAPI(apiKey: "x", transport: stub, retry: Self.quick).createRandomAlias()
        }
        #expect(stub.requests.count == 1)
    }

    @Test func cancellingDuringTheWaitStopsRetrying() async {
        let stub = StubTransport()
        for _ in 0..<3 { stub.enqueue(status: 503, json: #"{"error":"Busy"}"#) }
        let api = SimpleLoginAPI(apiKey: "x", transport: stub, retry: RetryPolicy(attempts: 3, delay: .seconds(10)))
        let task = Task { try await api.userInfo() }
        while stub.requests.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: APIError.server(status: 503, message: "Busy")) { try await task.value }
        #expect(stub.requests.count == 1)
    }

    @Test func theStandardPolicyTriesThreeTimesTwoSecondsApart() {
        #expect(RetryPolicy.standard == RetryPolicy(attempts: 3, delay: .seconds(2)))
    }

    @Test func transientErrorsAreNetworkFailuresRateLimitsAndServerErrors() {
        #expect(APIError.transport("offline").isTransient)
        #expect(APIError.server(status: 429, message: nil).isTransient)
        #expect(APIError.server(status: 500, message: nil).isTransient)
        #expect(APIError.server(status: 503, message: nil).isTransient)
        #expect(!APIError.unauthorized.isTransient)
        #expect(!APIError.server(status: 403, message: nil).isTransient)
        #expect(!APIError.server(status: 404, message: nil).isTransient)
        #expect(!APIError.decoding("bad").isTransient)
    }
}
