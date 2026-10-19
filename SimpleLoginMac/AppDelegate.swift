import AppKit
import SimpleLoginKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel

    override init() {
        model = AppModel(timerStore: Self.makeTimerStore())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isHostingUnitTests else { return }
        model.start()
    }

    /// Records of aliases that could not be disabled in time stay on disk for the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.engine.hasActiveTimers else { return .terminateNow }
        Task {
            await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func makeTimerStore() -> any TimerStore {
        do {
            return FileTimerStore(fileURL: try FileTimerStore.defaultURL())
        } catch {
            return UnavailableTimerStore(reason: error.localizedDescription)
        }
    }

    /// The test host must not touch the real Keychain item, timer file, or API.
    private static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// Stands in when the timer file's location can't be determined, so the menu reports
/// unreadable timer data instead of the app treating the timer list as empty.
struct UnavailableTimerStore: TimerStore {
    let reason: String

    func load() throws -> [TimerRecord] {
        throw TimerStoreError.unreadable(reason)
    }

    func save(_ records: [TimerRecord]) throws {
        throw TimerStoreError.unreadable(reason)
    }
}
