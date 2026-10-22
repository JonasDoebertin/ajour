import Foundation
import SimpleLoginKit
import Testing
@testable import Ajour

struct AliasStatusTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let german = Locale(identifier: "de_DE")
    private let american = Locale(identifier: "en_US")

    private func berlinTime(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: hour, minute: minute))!
    }

    private func timed(remaining: TimeInterval, length: TimeInterval = 3600, endsAt: Date? = nil) -> AliasMenuState {
        .timed(remaining: remaining, endsAt: endsAt ?? berlinTime(hour: 14, minute: 12), length: length)
    }

    private func status(
        _ state: AliasMenuState,
        activity: Ajour.AliasActivity? = nil,
        reducesMotion: Bool = false,
        locale: Locale? = nil
    ) -> AliasStatus {
        AliasStatus.make(state: state, activity: activity, reducesMotion: reducesMotion, locale: locale ?? german, timeZone: berlin)
    }

    private func shareLeft(of status: AliasStatus) -> Double? {
        guard case .timed(let shareLeft) = status.kind else { return nil }
        return shareLeft
    }

    private func label(
        pinned: Bool = false,
        state: AliasMenuState,
        activity: Ajour.AliasActivity? = nil,
        email: String = "github@alexmorgan.example"
    ) -> String {
        AliasStatus.accessibilityLabel(email: email, pinned: pinned, state: state, activity: activity, locale: german, timeZone: berlin)
    }

    @Test func enabledAndDisabledStatesUseTheirWords() {
        #expect(status(.enabled).kind == .enabled)
        #expect(status(.enabled).line == "Enabled")
        #expect(status(.disabled).kind == .disabled)
        #expect(status(.disabled).line == "Disabled")
        #expect(status(.enabled).turnsOff == nil)
    }

    @Test func timedStatusShowsTimeLeftAndTurnOffTime() {
        let status = status(timed(remaining: 272))

        #expect(status.words == "4:32 left")
        #expect(status.turnsOff == "off at 14:12")
        #expect(status.line == "4:32 left · off at 14:12")
    }

    @Test func turnOffTimeFollowsTwelveHourLocales() {
        #expect(status(timed(remaining: 272), locale: american).turnsOff == "off at 2:12\u{202F}PM")
    }

    @Test func timerOverAnHourUsesHours() {
        #expect(status(timed(remaining: 3600, length: 7200)).words == "1:00:00 left")
        #expect(status(timed(remaining: 3599, length: 7200)).words == "59:59 left")
    }

    @Test func shareLeftStaysWithinBounds() {
        #expect(shareLeft(of: status(timed(remaining: 600, length: 300))) == 1)
        #expect(shareLeft(of: status(timed(remaining: 0, length: 300))) == 0)
        #expect(shareLeft(of: status(timed(remaining: 150, length: 300))) == 0.5)
    }

    @Test func reducedMotionStepsThePieByMinutes() {
        #expect(shareLeft(of: status(timed(remaining: 61, length: 300), reducesMotion: true)) == 120.0 / 300)
        #expect(shareLeft(of: status(timed(remaining: 61, length: 300))) == 61.0 / 300)
    }

    @Test func reducedMotionKeepsTheCountdownTextExact() {
        #expect(status(timed(remaining: 61, length: 300), reducesMotion: true).words == "1:01 left")
    }

    @Test func busyAliasShowsItsActivity() {
        let status = status(.disabled, activity: .enabling)

        #expect(status.kind == .busy)
        #expect(status.line == "Enabling…")
        #expect(status.turnsOff == nil)
    }

    @Test func busyTimedAliasHidesItsTurnOffTime() {
        let status = status(timed(remaining: 272), activity: .updating)

        #expect(status.line == "Updating…")
        #expect(status.turnsOff == nil)
    }

    @Test func everyActivityHasItsWords() {
        #expect(Ajour.AliasActivity.enabling.words == "Enabling…")
        #expect(Ajour.AliasActivity.disabling.words == "Disabling…")
        #expect(Ajour.AliasActivity.updating.words == "Updating…")
    }

    @Test func voiceOverReadsTheWholeState() {
        let state = timed(remaining: 2820, endsAt: berlinTime(hour: 14, minute: 54))

        #expect(label(pinned: true, state: state, email: "travel@alexmorgan.example")
            == "travel@alexmorgan.example, pinned, enabled, 47 minutes left, turns off at 14:54")
    }

    @Test func voiceOverRoundsTimeLeftUpToWholeMinutes() {
        #expect(label(state: timed(remaining: 59)).contains("1 minute left"))
        #expect(label(state: timed(remaining: 61)).contains("2 minutes left"))
    }

    @Test func voiceOverLeavesOutPartsThatDoNotApply() {
        #expect(label(state: .enabled) == "github@alexmorgan.example, enabled")
        #expect(label(state: .disabled) == "github@alexmorgan.example, disabled")
        #expect(label(pinned: true, state: .disabled) == "github@alexmorgan.example, pinned, disabled")
    }

    @Test func voiceOverReadsTheActivityInsteadOfTheState() {
        #expect(label(state: .disabled, activity: .enabling) == "github@alexmorgan.example, enabling")
        #expect(label(pinned: true, state: timed(remaining: 120), activity: .disabling) == "github@alexmorgan.example, pinned, disabling")
    }

    @Test func aFailingDisableSaysItKeepsTrying() {
        let status = status(.disableFailing)

        #expect(status.kind == .stuck)
        #expect(status.line == "Not disabled · retrying")
    }

    @Test func aRefusedDisableNamesTheKey() {
        let status = status(.disableRefused)

        #expect(status.kind == .stuck)
        #expect(status.line == "Can't disable with this key")
        #expect(status.turnsOff == nil)
    }

    @Test func voiceOverReadsFailedAndRefusedDisables() {
        #expect(label(state: .disableFailing, email: "shop@example.com") == "shop@example.com, not disabled, Ajour keeps trying")
        #expect(label(pinned: true, state: .disableRefused, email: "shop@example.com")
            == "shop@example.com, pinned, can't be disabled with the current API key")
    }

    @Test func anActivityWinsOverAFailedDisable() {
        let status = status(.disableFailing, activity: .disabling)

        #expect(status.kind == .busy)
        #expect(status.line == "Disabling…")
        #expect(label(state: .disableRefused, activity: .disabling) == "github@alexmorgan.example, disabling")
    }
}
