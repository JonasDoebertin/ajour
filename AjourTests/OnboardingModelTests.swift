import Foundation
import Observation
import Testing
import SimpleLoginKit
@testable import Ajour

@MainActor
struct OnboardingModelTests {
    static let keyLikeText = String(repeating: "k", count: 60)
    static let rejectedKeyMessage = "SimpleLogin did not accept this key. Check that you copied all of it, or create a new one."

    let keyStore: InMemoryAPIKeyStore
    let transport = StubTransport()
    let launchAtLogin = FakeLaunchAtLogin()
    let appModel: AppModel
    let onboarding: OnboardingModel
    let notificationRequests = Counter()
    let notificationPermission = Gate()

    init(keyStore: InMemoryAPIKeyStore = InMemoryAPIKeyStore(), holdsNotificationPermission: Bool = false) {
        self.keyStore = keyStore
        appModel = AppModel(keyStore: keyStore, timerStore: InMemoryTimerStore(), transport: transport, retry: .once)
        let notificationRequests = notificationRequests
        let notificationPermission = notificationPermission
        onboarding = OnboardingModel(
            appModel: appModel,
            launchAtLogin: launchAtLogin.control,
            requestNotificationAuthorization: {
                notificationRequests.increment()
                if holdsNotificationPermission { await notificationPermission.wait() }
            }
        )
    }

    func confirmedOnboarding() async -> OnboardingModel {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        onboarding.showKeyEntry()
        onboarding.apiKey = "valid-key"
        await onboarding.submit()
        return onboarding
    }

    @Test func startsWithTheExplanation() {
        #expect(onboarding.step == .explain)
    }

    @Test func showKeyEntryMovesToTheKeyStep() {
        onboarding.showKeyEntry()

        #expect(onboarding.step == .enterKey)
    }

    @Test func clipboardSuggestionOffersKeyLikeTextWhileTheFieldIsEmpty() {
        #expect(onboarding.clipboardSuggestion(for: " \(Self.keyLikeText)\n") == Self.keyLikeText)
    }

    @Test func clipboardSuggestionIgnoresTextThatIsNotAKey() {
        #expect(onboarding.clipboardSuggestion(for: "https://example.com") == nil)
        #expect(onboarding.clipboardSuggestion(for: nil) == nil)
    }

    @Test func clipboardSuggestionIsNotOfferedOnceSomethingWasEntered() {
        onboarding.apiKey = "typed"

        #expect(onboarding.clipboardSuggestion(for: Self.keyLikeText) == nil)
    }

    @Test func canSubmitOnlyWithAKey() {
        onboarding.apiKey = "  \n"
        #expect(!onboarding.canSubmit)

        onboarding.apiKey = "valid-key"
        #expect(onboarding.canSubmit)
    }

    @Test func submitShowsTheAccountOfAValidKey() async {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        onboarding.showKeyEntry()
        onboarding.apiKey = "valid-key"

        await onboarding.submit()

        #expect(onboarding.step == .confirm(Fixtures.userInfo))
        #expect(onboarding.errorMessage == nil)
        #expect(keyStore.key == "valid-key")
        #expect(appModel.phase == .signedIn(Fixtures.userInfo))
    }

    @Test func submitBlocksAnotherSubmitWhileValidating() async {
        transport.holdNext("/api/user_info", json: Fixtures.userInfoJSON)
        onboarding.apiKey = "valid-key"
        let submit = Task { await onboarding.submit() }
        await transport.waitUntilARequestIsHeld()

        #expect(onboarding.isSubmitting)
        #expect(!onboarding.canSubmit)

        transport.release()
        await submit.value
        #expect(!onboarding.isSubmitting)
    }

    @Test func submitIgnoresWhitespaceAroundAPastedKey() async {
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        onboarding.apiKey = "  valid-key\n"

        await onboarding.submit()

        #expect(keyStore.key == "valid-key")
    }

    @Test func submitExplainsARejectedKey() async {
        transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)
        onboarding.showKeyEntry()
        onboarding.apiKey = "bad-key"

        await onboarding.submit()

        #expect(onboarding.step == .enterKey)
        #expect(onboarding.errorMessage == Self.rejectedKeyMessage)
        #expect(keyStore.key == nil)
    }

    @Test func submitExplainsAMissingConnection() async {
        onboarding.showKeyEntry()
        onboarding.apiKey = "valid-key"

        await onboarding.submit()

        #expect(onboarding.step == .enterKey)
        #expect(onboarding.errorMessage == "Could not reach SimpleLogin. Check your network connection.")
    }

    @Test func submitExplainsAKeychainFailure() async {
        let test = OnboardingModelTests(keyStore: InMemoryAPIKeyStore(failsToSave: true))
        test.transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        test.onboarding.showKeyEntry()
        test.onboarding.apiKey = "valid-key"

        await test.onboarding.submit()

        #expect(test.onboarding.step == .enterKey)
        #expect(test.onboarding.errorMessage == "The API key could not be saved to the Keychain.")
    }

    @Test func aNewSubmitClearsThePreviousError() async {
        transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        onboarding.apiKey = "bad-key"
        await onboarding.submit()

        onboarding.apiKey = "valid-key"
        await onboarding.submit()

        #expect(onboarding.errorMessage == nil)
    }

    @Test func confirmingTheAccountLeadsToTheFinalStep() async {
        let onboarding = await confirmedOnboarding()

        onboarding.confirmAccount()

        #expect(onboarding.step == .finish)
        #expect(!onboarding.isComplete)
    }

    @Test func confirmingAReplacementKeyCompletesWithoutTheFinalStep() async {
        onboarding.beginKeyReplacement()
        #expect(onboarding.step == .enterKey)
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        onboarding.apiKey = "replacement-key"
        await onboarding.submit()

        onboarding.confirmAccount()

        #expect(onboarding.isComplete)
        #expect(launchAtLogin.appliedSettings.isEmpty)
        #expect(notificationRequests.value == 0)
    }

    @Test func finishEnablesLaunchAtLoginAndAsksForNotificationPermission() async {
        let onboarding = await confirmedOnboarding()
        onboarding.confirmAccount()

        await onboarding.finish(launchAtLogin: true)

        #expect(launchAtLogin.appliedSettings == [true])
        #expect(notificationRequests.value == 1)
        #expect(onboarding.isComplete)
    }

    @Test func finishWithoutLaunchAtLoginLeavesItOff() async {
        let onboarding = await confirmedOnboarding()
        onboarding.confirmAccount()

        await onboarding.finish(launchAtLogin: false)

        #expect(launchAtLogin.appliedSettings.isEmpty)
        #expect(notificationRequests.value == 1)
        #expect(onboarding.isComplete)
    }

    @Test func finishCompletesEvenWhenLaunchAtLoginFails() async {
        let onboarding = await confirmedOnboarding()
        onboarding.confirmAccount()
        launchAtLogin.failure = LaunchAtLoginRefused()

        await onboarding.finish(launchAtLogin: true)

        #expect(onboarding.isComplete)
        #expect(notificationRequests.value == 1)
        #expect(onboarding.errorMessage == "Ajour could not be added to your login items. Allow it in System Settings › General › Login Items.")
    }

    @Test func finishKeepsTheWindowOpenToShowALaunchAtLoginFailure() async {
        let onboarding = await confirmedOnboarding()
        onboarding.confirmAccount()
        launchAtLogin.failure = LaunchAtLoginRefused()

        await onboarding.finish(launchAtLogin: true)

        #expect(!onboarding.closesWindow)
    }

    @Test func finishWithoutProblemsClosesTheWindow() async {
        let onboarding = await confirmedOnboarding()
        onboarding.confirmAccount()

        await onboarding.finish(launchAtLogin: true)

        #expect(onboarding.closesWindow)
    }

    @Test func finishRunsOnceWhenDoneIsPressedTwice() async {
        let test = OnboardingModelTests(holdsNotificationPermission: true)
        let onboarding = await test.confirmedOnboarding()
        onboarding.confirmAccount()
        let firstFinish = Task { await onboarding.finish(launchAtLogin: true) }
        await test.notificationPermission.waitUntilSomeoneWaits()
        #expect(onboarding.isFinishing)

        let secondFinish = Task { await onboarding.finish(launchAtLogin: true) }
        test.notificationPermission.open()
        await firstFinish.value
        await secondFinish.value

        #expect(test.notificationRequests.value == 1)
        #expect(!onboarding.isFinishing)
        #expect(onboarding.isComplete)
    }

    @Test func progressCountsFourSteps() async {
        #expect(onboarding.progress == OnboardingProgress(step: 1, total: 4))

        onboarding.showKeyEntry()
        #expect(onboarding.progress == OnboardingProgress(step: 2, total: 4))

        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        onboarding.apiKey = "valid-key"
        await onboarding.submit()
        #expect(onboarding.progress == OnboardingProgress(step: 3, total: 4))

        onboarding.confirmAccount()
        #expect(onboarding.progress == OnboardingProgress(step: 4, total: 4))
    }

    @Test func replacingAKeyHidesProgressAndBack() {
        onboarding.beginKeyReplacement()

        #expect(onboarding.progress == nil)
        #expect(!onboarding.canGoBack)
    }

    @Test func endingAKeyReplacementUpdatesTheProgressOnScreen() {
        onboarding.beginKeyReplacement()
        let progressChanged = ChangeFlag()
        withObservationTracking { _ = onboarding.progress } onChange: { progressChanged.set() }

        onboarding.reset()

        #expect(progressChanged.isSet)
        #expect(onboarding.progress == OnboardingProgress(step: 1, total: 4))
    }

    @Test func backIsOfferedOnlyAfterTheWelcome() async {
        #expect(!onboarding.canGoBack)

        onboarding.showKeyEntry()
        #expect(onboarding.canGoBack)

        let confirmed = await confirmedOnboarding()
        #expect(confirmed.canGoBack)

        confirmed.confirmAccount()
        #expect(!confirmed.canGoBack)
    }

    @Test func backReturnsToThePreviousStep() async {
        let onboarding = await confirmedOnboarding()

        onboarding.goBack()
        #expect(onboarding.step == .enterKey)

        onboarding.goBack()
        #expect(onboarding.step == .explain)
    }

    @Test func backClearsTheError() async {
        transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)
        onboarding.showKeyEntry()
        onboarding.apiKey = "bad-key"
        await onboarding.submit()

        onboarding.goBack()

        #expect(onboarding.errorMessage == nil)
    }

    @Test func rejectedKeyExplainsWhatToCheck() async {
        transport.enqueue("/api/user_info", status: 401, json: #"{"error":"Wrong api key"}"#)
        onboarding.showKeyEntry()
        onboarding.apiKey = "bad-key"

        await onboarding.submit()

        #expect(onboarding.errorMessage == Self.rejectedKeyMessage)
    }

    @Test func initialsUseFirstAndLastName() {
        #expect(OnboardingModel.initials(of: "Alex Morgan") == "AM")
        #expect(OnboardingModel.initials(of: "Alex") == "A")
        #expect(OnboardingModel.initials(of: "Alex van Morgan") == "AM")
        #expect(OnboardingModel.initials(of: "  ") == "?")
    }

    @Test func resetStartsOver() async {
        let onboarding = await confirmedOnboarding()
        onboarding.beginKeyReplacement()
        onboarding.apiKey = "draft"

        onboarding.reset()

        #expect(onboarding.step == .explain)
        #expect(onboarding.apiKey.isEmpty)
        #expect(onboarding.errorMessage == nil)
        #expect(!onboarding.isComplete)
    }
}

/// Holds callers of `wait()` until `open()`; once open, it lets everyone through.
@MainActor final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilSomeoneWaits() async {
        while waiters.isEmpty {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor final class Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
