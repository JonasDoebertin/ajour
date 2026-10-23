import Foundation

/// Why an expiry disable failed, in terms of what the person can do about it.
public enum DisableProblem: Hashable, Sendable {
    case unreachable
    case notResponding(status: Int)
    case keyRejected
    case refused
    case other

    public init(error: any Error) {
        switch error {
        case is URLError, APIError.transport:
            self = .unreachable
        case APIError.server(let status, _) where status == 429 || (500..<600).contains(status):
            self = .notResponding(status: status)
        case APIError.unauthorized:
            self = .keyRejected
        case APIError.server(status: 403, _):
            self = .refused
        default:
            self = .other
        }
    }
}
