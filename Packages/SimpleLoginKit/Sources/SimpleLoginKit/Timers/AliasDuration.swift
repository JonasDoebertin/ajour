import Foundation

public enum AliasDuration: CaseIterable, Sendable, Hashable {
    case fiveMinutes
    case oneHour
    case twentyFourHours

    public var seconds: TimeInterval {
        switch self {
        case .fiveMinutes: 300
        case .oneHour: 3600
        case .twentyFourHours: 86400
        }
    }

    public var title: String {
        switch self {
        case .fiveMinutes: "5 Minutes"
        case .oneHour: "1 Hour"
        case .twentyFourHours: "24 Hours"
        }
    }
}
