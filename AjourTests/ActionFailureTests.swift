import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

/// How an action's failure reaches Spotlight and Shortcuts: in the menu's words, except for cancellation.
@MainActor
struct ActionFailureTests {
    @Test func cancellationPassesThroughUnchanged() async {
        await #expect(throws: CancellationError.self) {
            try await explainingFailures { throw CancellationError() }
        }
    }

    @Test func otherFailuresCarryTheMenuWords() async throws {
        let menuWords = AppModel.userMessage(for: TimerEngineError.notSignedIn)

        let error = await #expect(throws: ActionFailure.self) {
            try await explainingFailures { throw TimerEngineError.notSignedIn }
        }

        let failure = try #require(error)
        #expect(failure.message == menuWords)
        #expect(failure.localizedDescription == menuWords)
        #expect(String(localized: failure.localizedStringResource) == menuWords)
    }
}
