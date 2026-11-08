import Foundation

/// Holds a downloaded update until Ajour is quiet or the user asks for it, so a relaunch never interrupts them.
@MainActor
final class PendingUpdateInstall {
    private let isQuiet: () -> Bool
    private var install: (() -> Void)?

    private(set) var isInstalling = false

    var isScheduled: Bool { install != nil }

    init(isQuiet: @escaping () -> Bool) {
        self.isQuiet = isQuiet
    }

    func schedule(_ install: @escaping () -> Void) {
        self.install = install
        evaluate()
    }

    func evaluate() {
        guard isScheduled, isQuiet() else { return }
        installNow()
    }

    func installNow() {
        guard let install else { return }
        self.install = nil
        isInstalling = true
        install()
    }

    func cancel() {
        install = nil
    }
}
