import Foundation

public struct TimerRecord: Codable, Equatable, Sendable {
    public var aliasID: Int
    public var email: String
    public var enabledAt: Date
    public var expiresAt: Date
    public var lastNotifiedActivityTimestamp: Date?

    public init(
        aliasID: Int,
        email: String,
        enabledAt: Date,
        expiresAt: Date,
        lastNotifiedActivityTimestamp: Date? = nil
    ) {
        self.aliasID = aliasID
        self.email = email
        self.enabledAt = enabledAt
        self.expiresAt = expiresAt
        self.lastNotifiedActivityTimestamp = lastNotifiedActivityTimestamp
    }
}
