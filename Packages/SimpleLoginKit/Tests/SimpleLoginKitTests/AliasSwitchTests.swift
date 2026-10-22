import Testing
@testable import SimpleLoginKit

@Suite struct AliasSwitchTests {
    private func makeSwitch(enabled: Bool) -> (AliasSwitch, FakeAliasAPI) {
        let api = FakeAliasAPI(aliases: [.fixture(id: 5, enabled: enabled)])
        return (AliasSwitch(api: api, retry: RetryPolicy(attempts: 3, delay: .zero)), api)
    }

    @Test func enableTogglesDisabledAlias() async throws {
        let (aliasSwitch, api) = makeSwitch(enabled: false)
        let alias = try await aliasSwitch.ensureEnabled(aliasID: 5)
        #expect(api.toggleCalls == [5])
        #expect(alias.enabled == true)
    }

    @Test func enableSkipsAlreadyEnabledAlias() async throws {
        let (aliasSwitch, api) = makeSwitch(enabled: true)
        let alias = try await aliasSwitch.ensureEnabled(aliasID: 5)
        #expect(api.toggleCalls.isEmpty)
        #expect(alias.enabled == true)
    }

    @Test func disableTogglesEnabledAlias() async throws {
        let (aliasSwitch, api) = makeSwitch(enabled: true)
        let alias = try await aliasSwitch.ensureDisabled(aliasID: 5)
        #expect(api.toggleCalls == [5])
        #expect(alias.enabled == false)
    }

    @Test func disableSkipsAlreadyDisabledAlias() async throws {
        let (aliasSwitch, api) = makeSwitch(enabled: false)
        let alias = try await aliasSwitch.ensureDisabled(aliasID: 5)
        #expect(api.toggleCalls.isEmpty)
        #expect(alias.enabled == false)
    }

    @Test func errorsPropagate() async {
        let (aliasSwitch, api) = makeSwitch(enabled: false)
        api.errors = [APIError.unauthorized]
        await #expect(throws: APIError.unauthorized) {
            try await aliasSwitch.ensureEnabled(aliasID: 5)
        }
    }

    @Test func aToggleThatFailedAfterArrivingIsNotRepeated() async throws {
        let (aliasSwitch, api) = makeSwitch(enabled: true)
        api.toggleErrorsAfterApplying = [APIError.transport("timed out")]

        let alias = try await aliasSwitch.ensureDisabled(aliasID: 5)

        #expect(alias.enabled == false)
        #expect(api.toggleCalls.count == 1)
        #expect(api.aliases[5]?.enabled == false)
    }

    @Test func aToggleThatFailedIsRetriedAfterReadingAgain() async throws {
        let (aliasSwitch, api) = makeSwitch(enabled: true)
        api.toggleErrors = [APIError.server(status: 503, message: nil)]

        let alias = try await aliasSwitch.ensureDisabled(aliasID: 5)

        #expect(alias.enabled == false)
        #expect(api.aliasCalls.count == 2)
        #expect(api.toggleCalls.count == 1)
    }

    @Test func atMostThreeTogglesAreSent() async {
        let (aliasSwitch, api) = makeSwitch(enabled: true)
        api.toggleErrors = Array(repeating: APIError.transport("offline"), count: 3)

        await #expect(throws: APIError.transport("offline")) {
            try await aliasSwitch.ensureDisabled(aliasID: 5)
        }
        #expect(api.aliasCalls.count == 3)
    }

    @Test func aRejectedToggleIsNotRetried() async {
        let (aliasSwitch, api) = makeSwitch(enabled: true)
        api.toggleErrors = [APIError.server(status: 403, message: nil)]

        await #expect(throws: APIError.server(status: 403, message: nil)) {
            try await aliasSwitch.ensureDisabled(aliasID: 5)
        }
        #expect(api.aliasCalls.count == 1)
    }
}
