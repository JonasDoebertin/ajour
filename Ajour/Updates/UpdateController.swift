import AppKit
import Observation
import Sparkle

/// Connects Sparkle to Ajour. Scheduled checks never open a window: an update found in the background is
/// announced by a notification and the menu, and a downloaded update waits for a quiet moment to restart Ajour.
@MainActor @Observable
final class UpdateController: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private static let quietMomentCheckInterval: TimeInterval = 60

    /// Debug builds, and with them demo mode, never update themselves.
    static var isSupported: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    private(set) var menuState: UpdateMenuState = .idle
    /// Only a relaunch keeps timers running across the quit. Installing on a regular quit doesn't relaunch.
    private(set) var isRelaunchingForUpdate = false

    @ObservationIgnored var onUpdateFound: (String) -> Void = { _ in }
    @ObservationIgnored var onUpdateSeen: () -> Void = {}

    @ObservationIgnored private let pendingInstall: PendingUpdateInstall
    @ObservationIgnored private var quietMomentChecks: Timer?
    @ObservationIgnored private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    private var updater: SPUUpdater { updaterController.updater }

    init(isQuiet: @escaping () -> Bool) {
        pendingInstall = PendingUpdateInstall(isQuiet: isQuiet)
        super.init()
    }

    func start() {
        updater.automaticallyChecksForUpdates = true
        updaterController.startUpdater()
    }

    /// Also brings an update that was already found to the front.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func restartToUpdate() {
        pendingInstall.installNow()
        stopQuietMomentChecksIfInstalling()
    }

    func evaluatePendingInstall() {
        pendingInstall.evaluate()
        stopQuietMomentChecksIfInstalling()
    }

    var control: UpdatesControl {
        UpdatesControl(
            installsAutomatically: { [updater] in updater.automaticallyDownloadsUpdates },
            setInstallsAutomatically: { [updater] in updater.automaticallyDownloadsUpdates = $0 },
            checkForUpdates: { [weak self] in self?.checkForUpdates() }
        )
    }

    private func stopQuietMomentChecksIfInstalling() {
        guard pendingInstall.isInstalling else { return }
        quietMomentChecks?.invalidate()
        quietMomentChecks = nil
    }

    private func checkForQuietMomentRegularly() {
        quietMomentChecks?.invalidate()
        quietMomentChecks = Timer.scheduledTimer(withTimeInterval: Self.quietMomentCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePendingInstall() }
        }
    }

    // MARK: SPUUpdaterDelegate

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        menuState = .readyToInstall(version: item.displayVersionString)
        pendingInstall.schedule(immediateInstallHandler)
        if !pendingInstall.isInstalling { checkForQuietMomentRegularly() }
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        isRelaunchingForUpdate = true
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        menuState = .available(version: update.displayVersionString)
        onUpdateFound(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onUpdateSeen()
    }

    /// A downloaded update keeps waiting for its restart after the session ends.
    func standardUserDriverWillFinishUpdateSession() {
        if case .available = menuState { menuState = .idle }
        onUpdateSeen()
    }
}
