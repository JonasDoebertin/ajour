#if DEBUG
import Foundation
import SimpleLoginKit

/// The sample account demo mode shows. Addresses use the reserved `example.com` domain.
enum DemoAccount {
    struct Alias {
        let id: Int
        let email: String
        var enabled: Bool
        var pinned: Bool
        var note: String?
        var forwarded = 0
        var blocked = 0
    }

    static let name = "Alex Morgan"
    static let email = "alex@example.com"
    static let customDomain = "alexmorgan.example"

    static let aliases: [Alias] = [
        Alias(id: 101, email: "newsletters@alexmorgan.example", enabled: true, pinned: true, note: "Tech and design newsletters", forwarded: 412, blocked: 3),
        Alias(id: 102, email: "travel@alexmorgan.example", enabled: true, pinned: true, note: "Flights, trains and hotels", forwarded: 58),
        Alias(id: 103, email: "online-shops@alexmorgan.example", enabled: false, pinned: true, note: "One-off orders", forwarded: 131, blocked: 27),
        Alias(id: 104, email: "signups@alexmorgan.example", enabled: false, pinned: true, note: "Trials and test accounts", forwarded: 76, blocked: 112),
        Alias(id: 105, email: "quiet.harbor42@example.com", enabled: true, pinned: false, note: "Wi-Fi at the airport lounge", forwarded: 1),
        Alias(id: 106, email: "github@alexmorgan.example", enabled: true, pinned: false, note: "Developer account", forwarded: 903),
        Alias(id: 107, email: "bank@alexmorgan.example", enabled: true, pinned: false, note: "Statements only", forwarded: 64),
        Alias(id: 108, email: "conference-2026@alexmorgan.example", enabled: false, pinned: false, note: "Ticket and schedule", forwarded: 22, blocked: 41),
        Alias(id: 109, email: "amber.falcon17@example.com", enabled: false, pinned: false, note: "Raffle at the bakery", forwarded: 2, blocked: 15),
        Alias(id: 110, email: "streaming@alexmorgan.example", enabled: true, pinned: false, note: nil, forwarded: 37),
        Alias(id: 111, email: "gym@alexmorgan.example", enabled: true, pinned: false, note: "Membership and class bookings", forwarded: 19),
        Alias(id: 112, email: "real-estate@alexmorgan.example", enabled: false, pinned: false, note: "Flat hunting", forwarded: 88, blocked: 230),
    ]

    /// Aliases that start with a running timer, with the seconds left.
    /// Timers that started a while ago, so their countdown pies are partly used up.
    static var timedAliases: [(alias: Alias, remaining: TimeInterval, length: TimeInterval)] {
        let byID = Dictionary(uniqueKeysWithValues: aliases.map { ($0.id, $0) })
        return [
            (byID[102]!, 47 * 60 + 12, AliasDuration.oneHour.seconds),
            (byID[105]!, 4 * 60 + 38, AliasDuration.fiveMinutes.seconds),
        ]
    }

    static let suffixes: [(suffix: String, isCustom: Bool)] = [
        ("@alexmorgan.example", true),
        (".brisk@example.com", false),
        (".meadow@example.com", false),
    ]

    static let randomAliasNames = ["calm.river58", "silver.otter23", "gentle.comet91", "bright.maple66"]
}
#endif
