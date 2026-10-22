import Testing
@testable import Ajour

struct ProblemMessageTests {
    @Test func messageSplitsAfterTheFirstSentence() {
        let message = ProblemMessage("Could not reach SimpleLogin. Check your network connection.")
        #expect(message.title == "Could not reach SimpleLogin.")
        #expect(message.detail == "Check your network connection.")
    }

    @Test func singleSentenceIsAllTitle() {
        let message = ProblemMessage("Timer data unreadable")
        #expect(message.title == "Timer data unreadable")
        #expect(message.detail == nil)
    }

    @Test func decimalPointIsNoSentenceEnd() {
        let message = ProblemMessage("Version 1.2 is required")
        #expect(message.title == "Version 1.2 is required")
        #expect(message.detail == nil)
    }
}
