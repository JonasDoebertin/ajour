import AppIntents
import SimpleLoginKit

enum EnableDuration: String, AppEnum {
    case fiveMinutes, oneHour, twentyFourHours

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Duration"
    static let caseDisplayRepresentations: [EnableDuration: DisplayRepresentation] = [
        .fiveMinutes: "5 Minutes",
        .oneHour: "1 Hour",
        .twentyFourHours: "24 Hours",
    ]

    var aliasDuration: AliasDuration {
        switch self {
        case .fiveMinutes: .fiveMinutes
        case .oneHour: .oneHour
        case .twentyFourHours: .twentyFourHours
        }
    }
}

enum CreationExpiry: String, AppEnum {
    case never, fiveMinutes, oneHour, twentyFourHours

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Expiry"
    static let caseDisplayRepresentations: [CreationExpiry: DisplayRepresentation] = [
        .never: "Never",
        .fiveMinutes: "5 Minutes",
        .oneHour: "1 Hour",
        .twentyFourHours: "24 Hours",
    ]

    var aliasDuration: AliasDuration? {
        switch self {
        case .never: nil
        case .fiveMinutes: .fiveMinutes
        case .oneHour: .oneHour
        case .twentyFourHours: .twentyFourHours
        }
    }
}
