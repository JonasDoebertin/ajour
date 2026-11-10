import Testing
import SimpleLoginKit
@testable import Ajour

/// What an action outside the menu says when it is done, and how its options map to the menu's durations.
struct ActionDialogTests {
    static let email = "quiet.harbor42@simplelogin.com"
    static let durations: [(AliasDuration, String)] = [
        (.fiveMinutes, "5 minutes"),
        (.oneHour, "1 hour"),
        (.twentyFourHours, "24 hours"),
    ]

    @Test(arguments: durations)
    func enabledNamesTheDuration(duration: AliasDuration, words: String) {
        let alias = EnabledAlias(email: Self.email, outcome: .enabled)

        #expect(ActionDialog.enabled(alias, duration: duration) == "\(Self.email) is enabled for \(words) and copied.")
    }

    @Test(arguments: durations)
    func extendedCountsFromNow(duration: AliasDuration, words: String) {
        let alias = EnabledAlias(email: Self.email, outcome: .extended)

        #expect(
            ActionDialog.enabled(alias, duration: duration)
                == "\(Self.email) stays enabled for \(words) from now and is copied."
        )
    }

    @Test(arguments: AliasDuration.allCases)
    func alreadyEnabledPromisesToLeaveItOn(duration: AliasDuration) {
        let alias = EnabledAlias(email: Self.email, outcome: .alreadyEnabled)

        #expect(
            ActionDialog.enabled(alias, duration: duration)
                == "\(Self.email) is already enabled and copied. Ajour won't turn it off."
        )
    }

    @Test func createdWithoutExpiry() {
        #expect(ActionDialog.created(email: Self.email, expiringAfter: nil) == "\(Self.email) is created and copied.")
    }

    @Test(arguments: durations)
    func createdWithExpiryNamesTheDuration(duration: AliasDuration, words: String) {
        #expect(
            ActionDialog.created(email: Self.email, expiringAfter: duration)
                == "\(Self.email) is created for \(words) and copied."
        )
    }

    @Test func disabled() {
        #expect(ActionDialog.disabled(email: Self.email) == "\(Self.email) is disabled.")
    }

    @Test func optionsMapToTheMenuDurations() {
        #expect(EnableDuration.allCases.map(\.aliasDuration) == AliasDuration.allCases)
        #expect(CreationExpiry.never.aliasDuration == nil)
        #expect(CreationExpiry.allCases.compactMap(\.aliasDuration) == AliasDuration.allCases)
    }
}
