import Foundation

/// How often a request is tried and how long to wait in between.
public struct RetryPolicy: Equatable, Sendable {
    public let attempts: Int
    public let delay: Duration

    public init(attempts: Int, delay: Duration) {
        self.attempts = attempts
        self.delay = delay
    }

    /// Rides out a brief outage, such as a network that is still coming back after wake.
    public static let standard = RetryPolicy(attempts: 3, delay: .seconds(2))

    /// No retries, so a failing request fails right away.
    public static let once = RetryPolicy(attempts: 1, delay: .zero)
}
