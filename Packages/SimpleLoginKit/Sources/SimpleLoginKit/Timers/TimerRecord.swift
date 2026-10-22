import Foundation

public struct TimerRecord: Codable, Equatable, Sendable {
    public var aliasID: Int
    public var email: String
    public var enabledAt: Date
    public var expiresAt: Date
    public var lastNotifiedActivityTimestamp: Date?
    /// Set once the person was told the key may not disable this alias, so a repeated refusal stays silent.
    public var refusalReportedAt: Date?

    public init(
        aliasID: Int,
        email: String,
        enabledAt: Date,
        expiresAt: Date,
        lastNotifiedActivityTimestamp: Date? = nil,
        refusalReportedAt: Date? = nil
    ) {
        self.aliasID = aliasID
        self.email = email
        self.enabledAt = enabledAt
        self.expiresAt = expiresAt
        self.lastNotifiedActivityTimestamp = lastNotifiedActivityTimestamp
        self.refusalReportedAt = refusalReportedAt
    }
}
