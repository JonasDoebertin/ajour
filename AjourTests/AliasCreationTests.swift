import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

/// Creating random and custom aliases: copying, announcing, and timing them.
@MainActor
final class AliasCreationTests {
    let timerStore: any TimerStore
    let transport = StubTransport()
    let clock = TestClock()
    private(set) var copied: [String] = []
    private(set) var announced: [String] = []

    init() {
        timerStore = InMemoryTimerStore()
    }

    init(timerStore: any TimerStore) {
        self.timerStore = timerStore
    }

    func makeModel(disableBudget: Duration = .seconds(5)) -> AppModel {
        let clock = clock
        let model = AppModel(
            keyStore: InMemoryAPIKeyStore(),
            timerStore: timerStore,
            transport: transport,
            now: { clock.now },
            copyToClipboard: { [weak self] in self?.copied.append($0) },
            disableBudget: disableBudget
        )
        model.onNewAliasCopied = { [weak self] in self?.announced.append($0) }
        return model
    }

    func signedInModel(disableBudget: Duration = .seconds(5)) async throws -> AppModel {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        let model = makeModel(disableBudget: disableBudget)
        _ = try await model.signIn(apiKey: "valid-key")
        return model
    }

    func requestCount(path: String) -> Int {
        transport.requests.filter { $0.url?.path == path }.count
    }

    func enqueueRandomAlias(id: Int = 42, email: String = "random@example.com") {
        transport.enqueue("/api/alias/random/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: id, email: email))
    }

    static let customSuffix = AliasSuffix(suffix: "@my.dev", signedSuffix: "@my.dev.signed", isCustom: true, isPremium: false)

    @Test func aRandomAliasIsCopiedAndAnnounced() async throws {
        let model = try await signedInModel()
        enqueueRandomAlias()

        await model.createRandomAlias(expiringAfter: nil)

        #expect(copied == ["random@example.com"])
        #expect(announced == ["random@example.com"])
        #expect(model.engine.records.isEmpty)
        #expect(model.lastError == nil)
    }

    @Test func aRandomAliasThatCouldNotBeCreatedShowsWhy() async throws {
        let model = try await signedInModel()

        await model.createRandomAlias(expiringAfter: nil)

        #expect(model.lastError == "Could not reach SimpleLogin. Check your network connection.")
        #expect(copied.isEmpty)
        #expect(announced.isEmpty)
    }

    @Test func aRandomAliasWhileSignedOutExplainsThatSetupIsMissing() async {
        let model = makeModel()
        model.start()

        await model.createRandomAlias(expiringAfter: nil)

        #expect(model.lastError == "Not signed in. Set up your API key first.")
    }

    @Test func anExpiringRandomAliasAppearsInTheTimedSection() async throws {
        let model = try await signedInModel()
        enqueueRandomAlias()

        await model.createRandomAlias(expiringAfter: .oneHour)

        #expect(model.engine.record(for: 42)?.expiresAt == clock.now.addingTimeInterval(3600))
        #expect(model.menuSections.timedUnpinned == [MenuAliasItem(id: 42, email: "random@example.com", state: .timed(remaining: 3600))])
        #expect(model.menuSections.pinned.isEmpty)
        #expect(copied == ["random@example.com"])
        #expect(announced == ["random@example.com"])
        #expect(requestCount(path: "/api/aliases/42/toggle") == 0)
    }

    @Test func anExpiringRandomAliasWhoseTimerCannotStartIsDisabledAgain() async throws {
        let test = AliasCreationTests(timerStore: UnavailableTimerStore(reason: "test"))
        let model = try await test.signedInModel()
        test.enqueueRandomAlias()
        test.transport.enqueue("/api/aliases/42", json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        test.transport.enqueue("/api/aliases/42/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.createRandomAlias(expiringAfter: .fiveMinutes)

        #expect(test.requestCount(path: "/api/aliases/42/toggle") == 1)
        #expect(model.lastError == "Timer data is unreadable, so timers can't be started or changed.")
        #expect(test.copied.isEmpty)
        #expect(test.announced.isEmpty)
    }

    @Test func anExpiringRandomAliasWhoseTimerCannotBeSavedIsDisabledAndForgotten() async throws {
        let test = AliasCreationTests(timerStore: InMemoryTimerStore(failsToSave: true))
        let model = try await test.signedInModel()
        test.enqueueRandomAlias()
        test.transport.enqueue("/api/aliases/42", json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        test.transport.enqueue("/api/aliases/42/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.createRandomAlias(expiringAfter: .fiveMinutes)

        #expect(test.requestCount(path: "/api/aliases/42/toggle") == 1)
        #expect(model.engine.records.isEmpty)
        #expect(model.lastError != nil)
    }

    @Test func anExpiringRandomAliasThatStaysEnabledWithoutATimerSaysSo() async throws {
        let test = AliasCreationTests(timerStore: UnavailableTimerStore(reason: "test"))
        let model = try await test.signedInModel()
        test.enqueueRandomAlias()

        await model.createRandomAlias(expiringAfter: .fiveMinutes)

        #expect(model.lastError == "random@example.com was created, but its timer could not start and it is still enabled.")
    }

    @Test func quittingWhileAnExpiringAliasIsCreatedDisablesItOnceItsTimerRuns() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/alias/random/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        transport.enqueue("/api/aliases/42", json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        transport.enqueue("/api/aliases/42/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let create = Task { await model.createRandomAlias(expiringAfter: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()

        let quit = Task { await model.prepareForTermination() }
        for _ in 0..<20 { await Task.yield() }
        transport.release()
        await create.value
        await quit.value

        #expect(requestCount(path: "/api/aliases/42/toggle") == 1)
        #expect(model.engine.records.isEmpty)
    }

    @Test func signingOutWhileAnExpiringAliasIsCreatedDisablesItOnceItsTimerRuns() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/alias/random/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        transport.enqueue("/api/aliases/42", json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        transport.enqueue("/api/aliases/42/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let create = Task { await model.createRandomAlias(expiringAfter: .fiveMinutes) }
        await transport.waitUntilARequestIsHeld()

        let signOut = Task { try await model.signOut() }
        for _ in 0..<20 { await Task.yield() }
        transport.release()
        await create.value
        try await signOut.value

        #expect(requestCount(path: "/api/aliases/42/toggle") == 1)
        #expect(model.engine.records.isEmpty)
        #expect(model.phase == .signedOut)
        #expect(model.lastError == nil)
    }

    /// Starts creating a random alias that is held at the server, then signs out, giving up on it before it arrives.
    func createRandomAliasAcrossSignOut(model: AppModel, expiringAfter duration: AliasDuration?) async throws {
        transport.holdNext("/api/alias/random/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        let create = Task { await model.createRandomAlias(expiringAfter: duration) }
        await transport.waitUntilARequestIsHeld()
        try await model.signOut()
        transport.release()
        await create.value
    }

    @Test func anExpiringRandomAliasCreatedWhileSigningOutIsDisabledWithThePreviousKey() async throws {
        let model = try await signedInModel(disableBudget: .milliseconds(50))
        transport.enqueue("/api/aliases/42", json: Fixtures.newAliasJSON(id: 42, email: "random@example.com"))
        transport.enqueue("/api/aliases/42/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        try await createRandomAliasAcrossSignOut(model: model, expiringAfter: .fiveMinutes)

        let toggle = transport.requests.filter { $0.url?.path == "/api/aliases/42/toggle" }
        #expect(toggle.map { $0.value(forHTTPHeaderField: "Authentication") } == ["valid-key"])
        #expect(model.engine.records.isEmpty)
        #expect(copied.isEmpty)
        #expect(announced.isEmpty)
        #expect(model.lastError == "random@example.com was created for the previous account and has been disabled.")
    }

    @Test func anExpiringRandomAliasCreatedWhileSigningOutSaysWhenItStaysEnabled() async throws {
        let model = try await signedInModel(disableBudget: .milliseconds(50))

        try await createRandomAliasAcrossSignOut(model: model, expiringAfter: .fiveMinutes)

        #expect(model.engine.records.isEmpty)
        #expect(model.lastError == "random@example.com was created for the previous account and could not be disabled.")
    }

    @Test func aRandomAliasWithoutExpiryCreatedWhileSigningOutStaysEnabled() async throws {
        let model = try await signedInModel(disableBudget: .milliseconds(50))

        try await createRandomAliasAcrossSignOut(model: model, expiringAfter: nil)

        #expect(requestCount(path: "/api/aliases/42/toggle") == 0)
        #expect(copied.isEmpty)
        #expect(announced.isEmpty)
        #expect(model.lastError == "random@example.com was created for the previous account.")
    }

    @Test func anExpiringCustomAliasCreatedWhileTheKeyChangesIsDisabledWithThePreviousKey() async throws {
        let model = try await signedInModel()
        transport.holdNext("/api/v3/alias/custom/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 50, email: "shop@my.dev"))
        transport.enqueue("/api/aliases/50", json: Fixtures.newAliasJSON(id: 50, email: "shop@my.dev"))
        transport.enqueue("/api/aliases/50/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        let create = Task { try await model.createCustomAlias(prefix: "shop", suffix: Self.customSuffix, mailboxID: 3, expiringAfter: .oneHour) }
        await transport.waitUntilARequestIsHeld()

        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await model.signIn(apiKey: "other-account-key")
        transport.release()

        await #expect(throws: AliasCreationError.disabledAfterAccountChange(email: "shop@my.dev")) { try await create.value }
        let toggle = transport.requests.filter { $0.url?.path == "/api/aliases/50/toggle" }
        #expect(toggle.map { $0.value(forHTTPHeaderField: "Authentication") } == ["valid-key"])
        #expect(model.engine.records.isEmpty)
        #expect(copied.isEmpty)
        #expect(announced.isEmpty)
    }

    @Test func aCustomAliasIsCreatedWithTheChosenSuffixAndMailbox() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v3/alias/custom/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 50, email: "shop@my.dev"))

        let alias = try await model.createCustomAlias(prefix: "shop", suffix: Self.customSuffix, mailboxID: 3, expiringAfter: nil)

        let requestBody = try #require(transport.requests.last?.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(body["alias_prefix"] as? String == "shop")
        #expect(body["signed_suffix"] as? String == "@my.dev.signed")
        #expect(body["mailbox_ids"] as? [Int] == [3])
        #expect(alias.email == "shop@my.dev")
        #expect(copied == ["shop@my.dev"])
        #expect(announced == ["shop@my.dev"])
        #expect(model.engine.records.isEmpty)
    }

    @Test func aCustomAliasWithAnExpiryStartsATimer() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v3/alias/custom/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 50, email: "shop@my.dev"))

        _ = try await model.createCustomAlias(prefix: "shop", suffix: Self.customSuffix, mailboxID: 3, expiringAfter: .twentyFourHours)

        #expect(model.menuSections.timedUnpinned == [MenuAliasItem(id: 50, email: "shop@my.dev", state: .timed(remaining: 86400))])
    }

    @Test func aRejectedCustomAliasPassesOnTheServerError() async throws {
        let model = try await signedInModel()
        transport.enqueue("/api/v3/alias/custom/new", method: "POST", status: 400, json: #"{"error":"Prefix can only contain letters"}"#)

        await #expect(throws: APIError.server(status: 400, message: "Prefix can only contain letters")) {
            try await model.createCustomAlias(prefix: "ä!", suffix: Self.customSuffix, mailboxID: 3, expiringAfter: nil)
        }
        #expect(copied.isEmpty)
        #expect(announced.isEmpty)
    }
}
