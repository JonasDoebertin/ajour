import SimpleLoginKit

/// What an action outside the menu says once it is done.
enum ActionDialog {
    static func enabled(_ alias: EnabledAlias, duration: AliasDuration) -> String {
        switch alias.outcome {
        case .enabled:
            "\(alias.email) is enabled for \(words(for: duration)) and copied."
        case .extended:
            "\(alias.email) stays enabled for \(words(for: duration)) from now and is copied."
        case .alreadyEnabled:
            "\(alias.email) is already enabled and copied. Ajour won't turn it off."
        }
    }

    static func created(email: String, expiringAfter duration: AliasDuration?) -> String {
        guard let duration else { return "\(email) is created and copied." }
        return "\(email) is created for \(words(for: duration)) and copied."
    }

    static func disabled(email: String) -> String {
        "\(email) is disabled."
    }

    private static func words(for duration: AliasDuration) -> String {
        switch duration {
        case .fiveMinutes: "5 minutes"
        case .oneHour: "1 hour"
        case .twentyFourHours: "24 hours"
        }
    }
}
