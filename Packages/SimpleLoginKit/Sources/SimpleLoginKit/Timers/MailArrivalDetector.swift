import Foundation

public struct MailArrival: Equatable, Sendable {
    public let aliasID: Int
    public let aliasEmail: String
    public let sender: String
    public let timestamp: Date

    public init(aliasID: Int, aliasEmail: String, sender: String, timestamp: Date) {
        self.aliasID = aliasID
        self.aliasEmail = aliasEmail
        self.sender = sender
        self.timestamp = timestamp
    }
}

public enum MailArrivalDetector {
    /// Returns the alias's latest activity when it is a forwarded mail that arrived while the timer
    /// ran and has not been reported yet.
    ///
    /// Activity timestamps have whole-second precision and the timer file drops sub-seconds, so the
    /// already-notified check compares whole seconds. Otherwise a reloaded record would report the
    /// same mail again.
    public static func arrival(in alias: Alias, for record: TimerRecord, clockSkew: TimeInterval = 5) -> MailArrival? {
        guard let activity = alias.latestActivity, activity.action == .forward else { return nil }
        guard activity.timestamp >= record.enabledAt.addingTimeInterval(-clockSkew) else { return nil }
        if let lastNotified = record.lastNotifiedActivityTimestamp,
           wholeSeconds(of: activity.timestamp) <= wholeSeconds(of: lastNotified) {
            return nil
        }
        return MailArrival(
            aliasID: alias.id,
            aliasEmail: alias.email,
            sender: activity.contact.email,
            timestamp: activity.timestamp
        )
    }

    private static func wholeSeconds(of date: Date) -> TimeInterval {
        date.timeIntervalSince1970.rounded(.down)
    }
}
