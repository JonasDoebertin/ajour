import Testing
@testable import SimpleLoginKit

@Suite struct AliasSwitchTests {
    private func makeSwitch(enabled: Bool) -> (AliasSwitch, FakeAliasAPI) {
        let api = FakeAliasAPI(aliases: [.fixture(id: 5, enabled: enabled)])
        return (AliasSwitch(api: api), api)
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
}
