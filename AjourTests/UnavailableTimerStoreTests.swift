import Testing
import SimpleLoginKit
@testable import Ajour

@MainActor
struct UnavailableTimerStoreTests {
    @Test func reportsTimerDataAsUnreadableInsteadOfEmpty() {
        let model = AppModel(keyStore: InMemoryAPIKeyStore(), timerStore: UnavailableTimerStore(reason: "no location"), retry: .once)

        #expect(model.engine.loadError == .unreadable("no location"))
    }
}
