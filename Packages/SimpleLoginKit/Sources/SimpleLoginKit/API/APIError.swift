import Foundation

public enum APIError: Error, Equatable, Sendable {
    case unauthorized
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)

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
