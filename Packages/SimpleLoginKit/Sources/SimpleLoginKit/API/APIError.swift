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
