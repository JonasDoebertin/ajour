import Foundation
import SimpleLoginKit

/// What the app is doing to an alias right now.
enum AliasActivity: Equatable {
    case enabling, disabling, updating

    var words: String {
        switch self {
        case .enabling: "Enabling…"
        case .disabling: "Disabling…"
        case .updating: "Updating…"
        }
    }

    fileprivate var spokenWords: String {
        words.dropLast().lowercased()
    }
}

/// The words and shape of an alias's state, shared by the menu and All Aliases.
struct AliasStatus: Equatable {
    enum Kind: Equatable {
        /// `stuck` is a timer that ran out without the alias being switched off.
        case enabled, disabled, timed(shareLeft: Double), busy, stuck
    }

    let kind: Kind
    let words: String
    let turnsOff: String?

    var line: String {
        guard let turnsOff else { return words }
        return "\(words) · \(turnsOff)"
    }

    /// With reduced motion, the pie's share steps once per minute, while the words keep counting every second.
    static func make(
        state: AliasMenuState,
        activity: AliasActivity?,
        reducesMotion: Bool = false,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> AliasStatus {
        if let activity {
            return AliasStatus(kind: .busy, words: activity.words, turnsOff: nil)
        }
        switch state {
        case .enabled:
            return AliasStatus(kind: .enabled, words: "Enabled", turnsOff: nil)
        case .disabled:
            return AliasStatus(kind: .disabled, words: "Disabled", turnsOff: nil)
        case .timed(let remaining, let endsAt, let length):
            let steppedRemaining = reducesMotion ? TimeInterval(wholeMinutes(of: remaining)) * 60 : remaining
            return AliasStatus(
                kind: .timed(shareLeft: min(max(steppedRemaining / length, 0), 1)),
                words: "\(RemainingTime.format(remaining)) left",
                turnsOff: "off at \(shortTime(endsAt, locale: locale, timeZone: timeZone))"
            )
        case .disableFailing:
            return AliasStatus(kind: .stuck, words: "Not disabled · retrying", turnsOff: nil)
        case .disableRefused:
            return AliasStatus(kind: .stuck, words: "Can't disable with this key", turnsOff: nil)
        }
    }

    static func accessibilityLabel(
        email: String,
        pinned: Bool,
        state: AliasMenuState,
        activity: AliasActivity?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var parts = [email]
        if pinned { parts.append("pinned") }
        if let activity {
            parts.append(activity.spokenWords)
            return parts.joined(separator: ", ")
        }
        switch state {
        case .disabled:
            parts.append("disabled")
        case .enabled:
            parts.append("enabled")
        case .timed(let remaining, let endsAt, _):
            let minutes = max(wholeMinutes(of: remaining), 1)
            parts.append("enabled")
            parts.append(minutes == 1 ? "1 minute left" : "\(minutes) minutes left")
            parts.append("turns off at \(shortTime(endsAt, locale: locale, timeZone: timeZone))")
        case .disableFailing:
            parts += ["not disabled", "Ajour keeps trying"]
        case .disableRefused:
            parts.append("can't be disabled with the current API key")
        }
        return parts.joined(separator: ", ")
    }

    private static func wholeMinutes(of seconds: TimeInterval) -> Int {
        Int((max(0, seconds) / 60).rounded(.up))
    }

    static func shortTime(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
