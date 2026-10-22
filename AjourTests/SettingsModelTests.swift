import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

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
        timerStore: (any TimerStore)? = nil,
        launchAtLogin: FakeLaunchAtLogin = FakeLaunchAtLogin()
    ) {
        self.keyStore = keyStore
        self.launchAtLogin = launchAtLogin
        appModel = AppModel(keyStore: keyStore, timerStore: timerStore ?? InMemoryTimerStore(records: records), transport: transport, retry: .once)
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

    @Test func aFailedLaunchAtLoginAdditionExplainsWhereToAllowIt() {
        launchAtLogin.failure = LaunchAtLoginRefused()

        settings.setLaunchAtLogin(true)

        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginError == "Ajour could not be added to your login items. Allow it in System Settings › General › Login Items.")
    }

    @Test func aFailedLaunchAtLoginRemovalExplainsWhereToRemoveIt() {
        launchAtLogin.isEnabled = true
        settings.refreshLaunchAtLogin()
        launchAtLogin.failure = LaunchAtLoginRefused()

        settings.setLaunchAtLogin(false)

        #expect(settings.launchAtLogin)
        #expect(settings.launchAtLoginError == "Ajour could not be removed from your login items. Remove it in System Settings › General › Login Items.")
    }

    @Test func openingLoginItemsOpensSystemSettings() {
        settings.openLoginItems()

        #expect(launchAtLogin.loginItemsOpened == 1)
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

    @Test func aBlockedSignOutOffersSigningOutAnyway() async throws {
        let test = SettingsModelTests(records: [.running(aliasID: 7)])
        try await test.signIn()

        await test.settings.signOut()

        #expect(test.appModel.phase == .signedIn(Fixtures.userInfo))
        #expect(test.settings.signOutError == nil)
        #expect(test.settings.blockedSignOut == .aliasesStillEnabled(
            [StillEnabledAlias(email: "shop@example.com", problem: .unreachable)],
            pendingEnables: 0
        ))
    }

    @Test func signingOutAnywaySignsOut() async throws {
        let test = SettingsModelTests(records: [.running(aliasID: 7)])
        try await test.signIn()
        await test.settings.signOut()

        await test.settings.signOutAnyway()

        #expect(test.appModel.phase == .signedOut)
        #expect(test.settings.blockedSignOut == nil)
        #expect(test.settings.signOutError == nil)
        #expect(!test.settings.isSigningOut)
    }

    @Test func signingOutAnywayThatCannotForgetTheTimersExplainsWhy() async throws {
        let timerStore = InMemoryTimerStore(records: [.running(aliasID: 7)], failsToSave: true)
        let test = SettingsModelTests(timerStore: timerStore)
        try await test.signIn()

        await test.settings.signOutAnyway()

        #expect(test.appModel.phase == .signedIn(Fixtures.userInfo))
        #expect(test.keyStore.key == "valid-key")
        #expect(test.settings.signOutError == SignOutError.timerDataUnreadable.userMessage)
    }

    @Test func signingOutAnywayThatCannotRemoveTheKeyExplainsWhyAndKeepsTheTimers() async throws {
        let timerStore = InMemoryTimerStore(records: [.running(aliasID: 7)])
        let test = SettingsModelTests(keyStore: InMemoryAPIKeyStore(failsToDelete: true), timerStore: timerStore)
        try await test.signIn()

        await test.settings.signOutAnyway()

        #expect(test.appModel.phase == .signedIn(Fixtures.userInfo))
        #expect(test.settings.signOutError == "The API key could not be removed from the Keychain.")
        #expect(test.appModel.engine.records.map(\.aliasID) == [7])
        #expect(timerStore.records.map(\.aliasID) == [7])
    }

    @Test func unreadableTimerDataKeepsTheCouldNotSignOutAlert() async throws {
        let test = SettingsModelTests(timerStore: UnavailableTimerStore(reason: "test"))
        try await test.signIn()

        await test.settings.signOut()

        #expect(test.settings.signOutError == SignOutError.timerDataUnreadable.userMessage)
        #expect(test.settings.blockedSignOut == nil)
    }

    @Test func aKeychainFailureDuringSignOutIsExplained() async throws {
        let test = SettingsModelTests(keyStore: InMemoryAPIKeyStore(failsToDelete: true))
        try await test.signIn()

        await test.settings.signOut()

        #expect(test.settings.signOutError == "The API key could not be removed from the Keychain.")
    }
}

private extension TimerRecord {
    static func running(aliasID: Int) -> TimerRecord {
        let now = Date()
        return TimerRecord(aliasID: aliasID, email: "shop@example.com", enabledAt: now, expiresAt: now.addingTimeInterval(300))
    }
}
