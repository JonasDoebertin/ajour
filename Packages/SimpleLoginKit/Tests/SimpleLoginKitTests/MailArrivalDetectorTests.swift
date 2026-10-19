import Foundation
import Testing
@testable import SimpleLoginKit

@Suite struct MailArrivalDetectorTests {
    private let enabledAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecord(lastNotified: Date? = nil) -> TimerRecord {
        TimerRecord(
            aliasID: 1,
            email: "shop@example.com",
            enabledAt: enabledAt,
            expiresAt: enabledAt.addingTimeInterval(300),
            lastNotifiedActivityTimestamp: lastNotified
        )
    }

    private func makeAlias(action: AliasActivity.Action = .forward, at timestamp: Date?) -> Alias {
        let activity = timestamp.map {
            AliasActivity(action: action, timestamp: $0, contact: AliasContact(email: "login@shop.com", name: nil))
        }
        return .fixture(id: 1, email: "shop@example.com", enabled: true, latestActivity: activity)
    }

    @Test func forwardAfterEnableIsArrival() {
        let timestamp = enabledAt.addingTimeInterval(30)

        let arrival = MailArrivalDetector.arrival(in: makeAlias(at: timestamp), for: makeRecord())

        #expect(arrival == MailArrival(
            aliasID: 1,
            aliasEmail: "shop@example.com",
            sender: "login@shop.com",
            timestamp: timestamp
        ))
    }

    @Test func forwardBeforeEnableIsIgnored() {
        let alias = makeAlias(at: enabledAt.addingTimeInterval(-60))

        #expect(MailArrivalDetector.arrival(in: alias, for: makeRecord()) == nil)
    }

    @Test func withinClockSkewCounts() {
        let alias = makeAlias(at: enabledAt.addingTimeInterval(-3))

        #expect(MailArrivalDetector.arrival(in: alias, for: makeRecord()) != nil)
    }

    @Test func justBeyondClockSkewIsIgnored() {
        let alias = makeAlias(at: enabledAt.addingTimeInterval(-6))

        #expect(MailArrivalDetector.arrival(in: alias, for: makeRecord()) == nil)
    }

    @Test(arguments: [AliasActivity.Action.block, .reply, .bounced, .other])
    func nonForwardActionIsIgnored(action: AliasActivity.Action) {
        let alias = makeAlias(action: action, at: enabledAt.addingTimeInterval(30))

        #expect(MailArrivalDetector.arrival(in: alias, for: makeRecord()) == nil)
    }

    @Test func aliasWithoutActivityIsIgnored() {
        #expect(MailArrivalDetector.arrival(in: makeAlias(at: nil), for: makeRecord()) == nil)
    }

    @Test func alreadyNotifiedIsIgnored() {
        let timestamp = enabledAt.addingTimeInterval(30)
        let record = makeRecord(lastNotified: timestamp)

        #expect(MailArrivalDetector.arrival(in: makeAlias(at: timestamp), for: record) == nil)
    }

    @Test func activityNewerThanLastNotifiedIsArrival() {
        let record = makeRecord(lastNotified: enabledAt.addingTimeInterval(30))
        let alias = makeAlias(at: enabledAt.addingTimeInterval(45))

        #expect(MailArrivalDetector.arrival(in: alias, for: record) != nil)
    }

    @Test func sameSecondAsTruncatedLastNotifiedIsIgnored() {
        let timestamp = enabledAt.addingTimeInterval(30.7)
        let record = makeRecord(lastNotified: enabledAt.addingTimeInterval(30))

        #expect(MailArrivalDetector.arrival(in: makeAlias(at: timestamp), for: record) == nil)
    }
}
