import Testing
import SimpleLoginKit
@testable import SimpleLoginMac

@MainActor
struct UnavailableTimerStoreTests {
    @Test func reportsTimerDataAsUnreadableInsteadOfEmpty() {
        let model = AppModel(keyStore: InMemoryAPIKeyStore(), timerStore: UnavailableTimerStore(reason: "no location"))

        #expect(model.engine.loadError == .unreadable("no location"))
    }
}
