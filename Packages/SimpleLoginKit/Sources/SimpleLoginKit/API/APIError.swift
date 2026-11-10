import Foundation

public enum APIError: Error, Equatable, Sendable {
    case unauthorized
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)

    /// Whether trying again could help: the network failed, or the server was busy or broken for a moment.
    public var isTransient: Bool {
        switch self {
        case .transport:
            true
        case .server(let status, _):
            status == 429 || (500...599).contains(status)
        case .unauthorized, .decoding:
            false
        }
    }

    public var userMessage: String {
        switch self {
        case .unauthorized:
            "The API key was rejected. Please sign in again."
        case .server(_, let message):
            message ?? "The server could not process the request."
        case .transport:
            "Could not reach SimpleLogin. Check your network connection."
        case .decoding:
            "Received an unexpected response from SimpleLogin."
        }
    }
}

extension APIError {
    /// SimpleLogin answers 404 or 400 "Unknown error" for aliases that don't exist. A 403 is different: the alias
    /// belongs to another account, for example after the key was replaced, and may still be enabled there.
    public static func meansAliasIsGone(_ error: any Error) -> Bool {
        switch error as? APIError {
        case .server(status: 404, _), .server(status: 400, message: "Unknown error"):
            true
        default:
            false
        }
    }
}
