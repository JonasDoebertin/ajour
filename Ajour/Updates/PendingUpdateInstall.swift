import Foundation

/// Holds a downloaded update until Ajour is quiet or the user asks for it, so a relaunch never interrupts them.
/// Without automatic installs, only the user starts it, or quitting Ajour installs it.
@MainActor
final class PendingUpdateInstall {
    private let installsAutomatically: () -> Bool
    private let isQuiet: () -> Bool
    private var install: (() -> Void)?

    var isScheduled: Bool { install != nil }

    init(installsAutomatically: @escaping () -> Bool, isQuiet: @escaping () -> Bool) {
        self.installsAutomatically = installsAutomatically
        self.isQuiet = isQuiet
    }

    func schedule(_ install: @escaping () -> Void) {
        self.install = install
        evaluate()
    }

    func evaluate() {
        guard isScheduled, installsAutomatically(), isQuiet() else { return }
        installNow()
    }

    func installNow() {
        guard let install else { return }
        self.install = nil
        install()
    }

    func cancel() {
        install = nil
    }
}
