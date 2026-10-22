#if DEBUG
import Foundation
import SimpleLoginKit
import Synchronization

/// Runs a Debug build against made-up sample data instead of a SimpleLogin account, for screenshots and UI work.
/// Nothing touches the Keychain, the timer file, or the network.
///
/// Start with `-AjourDemo YES`; add `-AjourDemoSignedOut YES` to start at onboarding.
enum DemoMode {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "AjourDemo")
    }

    @MainActor static func makeAppModel() -> AppModel {
        let startsSignedOut = UserDefaults.standard.bool(forKey: "AjourDemoSignedOut")
        let now = Date()
        let timers = DemoAccount.timedAliases.map { alias, remaining, length in
            let expiresAt = now.addingTimeInterval(remaining)
            return TimerRecord(aliasID: alias.id, email: alias.email, enabledAt: expiresAt.addingTimeInterval(-length), expiresAt: expiresAt)
        }
        return AppModel(
            keyStore: DemoKeyStore(key: startsSignedOut ? nil : "demo-key"),
            timerStore: DemoTimerStore(records: startsSignedOut ? [] : timers),
            transport: DemoTransport()
        )
    }
}

private final class DemoKeyStore: APIKeyStoring {
    private let key: Mutex<String?>

    init(key: String?) {
        self.key = Mutex(key)
    }

    func load() throws -> String? {
        key.withLock { $0 }
    }

    func save(_ key: String) throws {
        self.key.withLock { $0 = key }
    }

    func delete() throws {
        key.withLock { $0 = nil }
    }
}

private final class DemoTimerStore: TimerStore {
    private let records: Mutex<[TimerRecord]>

    init(records: [TimerRecord]) {
        self.records = Mutex(records)
    }

    func load() throws -> [TimerRecord] {
        records.withLock { $0 }
    }

    func save(_ records: [TimerRecord]) throws {
        self.records.withLock { $0 = records }
    }
}
#endif
