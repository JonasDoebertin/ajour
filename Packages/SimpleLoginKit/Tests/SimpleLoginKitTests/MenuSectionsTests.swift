import Foundation
import Testing
@testable import SimpleLoginKit

@Suite struct MenuSectionsTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func record(aliasID: Int, email: String = "timed@example.com", expiresIn seconds: TimeInterval) -> TimerRecord {
        TimerRecord(
            aliasID: aliasID,
            email: email,
            enabledAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(seconds)
        )
    }

    @Test func pinnedWithRecordIsTimed() {
        let pinned = [Alias.fixture(id: 1, email: "a@example.com", enabled: false)]
        let records = [record(aliasID: 1, expiresIn: 120)]

        let sections = MenuSections.make(pinned: pinned, records: records, now: now)

        #expect(sections.pinned == [MenuAliasItem(id: 1, email: "a@example.com", state: .timed(remaining: 120, endsAt: now.addingTimeInterval(120), length: 180))])
    }

    @Test func timedStateCarriesEndAndLength() {
        let records = [TimerRecord(
            aliasID: 1,
            email: "a@example.com",
            enabledAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(240)
        )]

        let sections = MenuSections.make(pinned: [], records: records, now: now)

        #expect(sections.timedUnpinned.map(\.state) == [
            .timed(remaining: 240, endsAt: now.addingTimeInterval(240), length: 300),
        ])
    }

    @Test func pinnedWithoutRecordFollowsEnabledFlag() {
        let pinned = [
            Alias.fixture(id: 1, email: "off@example.com", enabled: false),
            Alias.fixture(id: 2, email: "on@example.com", enabled: true),
        ]

        let sections = MenuSections.make(pinned: pinned, records: [], now: now)

        #expect(sections.pinned.map(\.state) == [.disabled, .enabled])
        #expect(sections.pinned.map(\.id) == [1, 2])
    }

    @Test func timedAliasNotPinnedGoesToOwnSection() {
        let pinned = [Alias.fixture(id: 1, email: "a@example.com")]
        let records = [
            record(aliasID: 9, email: "late@example.com", expiresIn: 600),
            record(aliasID: 8, email: "soon@example.com", expiresIn: 60),
        ]

        let sections = MenuSections.make(pinned: pinned, records: records, now: now)

        #expect(sections.timedUnpinned == [
            MenuAliasItem(id: 8, email: "soon@example.com", state: .timed(remaining: 60, endsAt: now.addingTimeInterval(60), length: 120)),
            MenuAliasItem(id: 9, email: "late@example.com", state: .timed(remaining: 600, endsAt: now.addingTimeInterval(600), length: 660)),
        ])
        #expect(sections.pinned.map(\.state) == [.disabled])
    }

    @Test func pinnedTimedAliasIsNotDuplicated() {
        let pinned = [Alias.fixture(id: 1)]
        let records = [record(aliasID: 1, expiresIn: 120)]

        let sections = MenuSections.make(pinned: pinned, records: records, now: now)

        #expect(sections.timedUnpinned.isEmpty)
        #expect(sections.pinned.count == 1)
    }

    @Test func expiredRecordShowsZeroRemaining() {
        let records = [record(aliasID: 9, expiresIn: -30)]

        let sections = MenuSections.make(pinned: [], records: records, now: now)

        #expect(sections.timedUnpinned.map(\.state) == [.timed(remaining: 0, endsAt: now.addingTimeInterval(-30), length: 30)])
    }

    @Test func formatsMinutesAndHours() {
        #expect(RemainingTime.format(299) == "4:59")
        #expect(RemainingTime.format(3540) == "59:00")
        #expect(RemainingTime.format(3600) == "1:00:00")
        #expect(RemainingTime.format(86399) == "23:59:59")
    }

    @Test func fractionalSecondsRoundUp() {
        #expect(RemainingTime.format(299.2) == "5:00")
        #expect(RemainingTime.format(3599.5) == "1:00:00")
        #expect(RemainingTime.format(0.4) == "0:01")
    }

    @Test func negativeRemainingClampsToZero() {
        #expect(RemainingTime.format(-5) == "0:00")
        #expect(RemainingTime.format(0) == "0:00")
    }
}
