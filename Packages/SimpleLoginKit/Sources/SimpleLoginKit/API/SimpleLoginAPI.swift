import Foundation

public struct SimpleLoginAPI: Sendable {
    public static let defaultBaseURL = URL(string: "https://app.simplelogin.io")!

    private let apiKey: String
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(apiKey: String, baseURL: URL = defaultBaseURL, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
    }

    public func userInfo() async throws -> UserInfo {
        try await send("GET", "/api/user_info")
    }

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws -> T {
        let request = try makeRequest(method, path, query: query, body: body)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
        do {
            return try Self.makeDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: (any Encodable)?) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.transport("Invalid base URL")
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw APIError.transport("Invalid request URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "Authentication")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
        default:
            let message = try? Self.makeDecoder().decode(ErrorBody.self, from: data).error
            throw APIError.server(status: response.statusCode, message: message)
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

private struct ErrorBody: Decodable {
    let error: String
}
