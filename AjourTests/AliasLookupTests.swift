import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

/// How the alias picker of an action finds aliases: suggestions, search and resolving chosen ones.
@MainActor
struct AliasLookupTests {
    let account = AliasActionsTests()
    var transport: StubTransport { account.transport }

    final class SleepRecorder {
        private(set) var durations: [Duration] = []
        var error: (any Error)?

        func sleep(_ duration: Duration) throws {
            durations.append(duration)
            if let error { throw error }
        }
    }

    func lookup(for model: AppModel, recorder: SleepRecorder = SleepRecorder()) -> AliasLookup {
        AliasLookup(appModel: model, sleep: { try recorder.sleep($0) })
    }

    func requests(method: String, path: String) -> [URLRequest] {
        transport.requests.filter { $0.httpMethod == method && $0.url?.path == path }
    }

    @Test func suggestionsArePinnedAliasesOnceLoaded() async throws {
        let model = try await account.signedInModel(pinned: [Fixtures.aliasJSON(id: 7)])
        let requestsBefore = transport.requests.count

        let suggestions = try await lookup(for: model).suggestions()

        #expect(suggestions.map(\.id) == [7])
        #expect(transport.requests.count == requestsBefore)
    }

    @Test func suggestionsLoadPinnedAliasesBeforeTheListHas() async throws {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = account.makeModel()
        _ = try await model.signIn(apiKey: "valid-key")
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: [3]))

        let suggestions = try await lookup(for: model).suggestions()

        #expect(suggestions.map(\.id) == [3])
        let sent = requests(method: "GET", path: "/api/v2/aliases")
        #expect(sent.count == 1)
        #expect(sent.first?.url?.query?.contains("pinned") == true)
    }

    @Test func suggestionsFailWhenSignedOut() async {
        let model = account.makeModel()
        model.start()

        await #expect(throws: TimerEngineError.notSignedIn) {
            try await lookup(for: model).suggestions()
        }
    }

    @Test func searchSendsOneRequestAfterTheDelay() async throws {
        let model = try await account.signedInModel()
        let recorder = SleepRecorder()
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: [5]))

        let found = try await lookup(for: model, recorder: recorder).search("shop")

        #expect(found.map(\.id) == [5])
        #expect(recorder.durations == [.milliseconds(300)])
        #expect(requests(method: "POST", path: "/api/v2/aliases").count == 1)
    }

    @Test func blankSearchShowsSuggestions() async throws {
        let model = try await account.signedInModel(pinned: [Fixtures.aliasJSON(id: 7)])

        let found = try await lookup(for: model).search("  ")

        #expect(found.map(\.id) == [7])
        #expect(requests(method: "POST", path: "/api/v2/aliases").isEmpty)
    }

    @Test func cancelledSearchSendsNothing() async throws {
        let model = try await account.signedInModel()
        let recorder = SleepRecorder()
        recorder.error = CancellationError()

        await #expect(throws: CancellationError.self) {
            try await lookup(for: model, recorder: recorder).search("shop")
        }
        #expect(requests(method: "POST", path: "/api/v2/aliases").isEmpty)
    }

    @Test func resolvingUsesPinnedAliasesAndReadsTheRest() async throws {
        let model = try await account.signedInModel(pinned: [Fixtures.aliasJSON(id: 7)])
        transport.enqueue("/api/aliases/9", json: Fixtures.aliasJSON(id: 9, pinned: false))

        let resolved = try await lookup(for: model).aliases(ids: [9, 7])

        #expect(resolved.map(\.id) == [9, 7])
        #expect(requests(method: "GET", path: "/api/aliases/9").count == 1)
        #expect(requests(method: "GET", path: "/api/aliases/7").isEmpty)
    }

    @Test func resolvingDropsDeletedAliases() async throws {
        let model = try await account.signedInModel()
        transport.enqueue("/api/aliases/9", status: 404, json: #"{"error":"Forbidden"}"#)

        let resolved = try await lookup(for: model).aliases(ids: [9])

        #expect(resolved.isEmpty)
    }

    @Test func resolvingFailsOnOtherErrors() async throws {
        let model = try await account.signedInModel()

        await #expect(throws: APIError.self) {
            try await lookup(for: model).aliases(ids: [9])
        }
    }
}
