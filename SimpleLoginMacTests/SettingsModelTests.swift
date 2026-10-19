import Foundation
import Testing
import SimpleLoginKit
@testable import SimpleLoginMac

@MainActor
struct SettingsModelTests {
    let keyStore: InMemoryAPIKeyStore
    let transport = StubTransport()
    let launchAtLogin: FakeLaunchAtLogin
    let appModel: AppModel
    let settings: SettingsModel

    init(
        keyStore: InMemoryAPIKeyStore = InMemoryAPIKeyStore(),
        records: [TimerRecord] = [],
        launchAtLogin: FakeLaunchAtLogin = FakeLaunchAtLogin()
    ) {
        self.keyStore = keyStore
        self.launchAtLogin = launchAtLogin
        appModel = AppModel(keyStore: keyStore, timerStore: InMemoryTimerStore(records: records), transport: transport)
        settings = SettingsModel(appModel: appModel, launchAtLogin: launchAtLogin.control)
    }

    func signIn() async throws {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await appModel.signIn(apiKey: "valid-key")
    }

    @Test func refreshingTheAccountRetriesALoadThatFailedAtLaunch() async {
        let test = SettingsModelTests(keyStore: InMemoryAPIKeyStore(key: "stored-key"))
        await test.appModel.start()?.value
        #expect(test.appModel.phase == .signedIn(nil))
        test.transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)

        await test.settings.refreshAccount()

        #expect(test.appModel.userInfo == Fixtures.userInfo)
    }

    @Test func refreshingTheAccountKeepsLoadedDetailsWithoutARequest() async throws {
        try await signIn()

        await settings.refreshAccount()

        #expect(transport.requests.count == 1)
        #expect(appModel.userInfo == Fixtures.userInfo)
    }

    @Test func refreshingTheAccountWhileSignedOutRequestsNothing() async {
        appModel.start()

        await settings.refreshAccount()

        #expect(transport.requests.isEmpty)
    }

    @Test func refreshReadsTheLaunchAtLoginState() {
        launchAtLogin.isEnabled = true

        settings.refreshLaunchAtLogin()

        #expect(settings.launchAtLogin)
    }

    @Test func settingLaunchAtLoginAppliesIt() {
        settings.setLaunchAtLogin(true)

        #expect(launchAtLogin.appliedSettings == [true])
        #expect(settings.launchAtLogin)
        #expect(settings.launchAtLoginError == nil)
    }

    @Test func aFailedLaunchAtLoginChangeShowsTheErrorAndTheActualState() {
        launchAtLogin.failure = LaunchAtLoginRefused()

        settings.setLaunchAtLogin(true)

        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginError == "Could not change launch at login. Operation not permitted")
    }

    @Test func aSuccessfulLaunchAtLoginChangeClearsThePreviousError() {
        launchAtLogin.failure = LaunchAtLoginRefused()
        settings.setLaunchAtLogin(true)
        launchAtLogin.failure = nil

        settings.setLaunchAtLogin(true)

        #expect(settings.launchAtLoginError == nil)
    }

    @Test func signOutSignsOut() async throws {
        try await signIn()

        await settings.signOut()

        #expect(appModel.phase == .signedOut)
        #expect(settings.signOutError == nil)
    }

    @Test func signOutIsInProgressUntilTimedAliasesAreDisabled() async throws {
        let now = Date()
        let record = TimerRecord(aliasID: 7, email: "shop@example.com", enabledAt: now, expiresAt: now.addingTimeInterval(300))
        let test = SettingsModelTests(records: [record])
        try await test.signIn()
        test.transport.holdNext("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        let signOut = Task { await test.settings.signOut() }
        await test.transport.waitUntilARequestIsHeld()

        #expect(test.settings.isSigningOut)

        test.transport.release()
        await signOut.value
        #expect(!test.settings.isSigningOut)
    }

    @Test func aBlockedSignOutExplainsWhy() async throws {
        let now = Date()
        let record = TimerRecord(aliasID: 7, email: "shop@example.com", enabledAt: now, expiresAt: now.addingTimeInterval(300))
        let test = SettingsModelTests(records: [record])
        try await test.signIn()

        await test.settings.signOut()

        #expect(test.appModel.phase == .signedIn(Fixtures.userInfo))
        #expect(test.settings.signOutError == "1 alias is still enabled. Check your connection and try again.")
    }

    @Test func aKeychainFailureDuringSignOutIsExplained() async throws {
        let test = SettingsModelTests(keyStore: InMemoryAPIKeyStore(failsToDelete: true))
        try await test.signIn()

        await test.settings.signOut()

        #expect(test.settings.signOutError == "The API key could not be removed from the Keychain.")
    }
}
