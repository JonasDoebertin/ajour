import Foundation

public struct SimpleLoginAPI: Sendable {
    public static let defaultBaseURL = URL(string: "https://app.simplelogin.io")!

    private let apiKey: String
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let retry: RetryPolicy

    public init(
        apiKey: String,
        baseURL: URL = defaultBaseURL,
        transport: any HTTPTransport = URLSessionTransport(),
        retry: RetryPolicy = .standard
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
        self.retry = retry
    }

    public func userInfo() async throws -> UserInfo {
        try await send("GET", "/api/user_info")
    }

    /// A request that is not `repeatable` changes something on the server, so it is only tried again when
    /// it certainly never left this Mac. Otherwise a lost answer could make it happen twice.
    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        repeatable: Bool = true
    ) async throws -> T {
        let request = try makeRequest(method, path, query: query, body: body)
        let data = try await sendWithRetries(request, repeatable: repeatable)
        do {
            return try Self.makeDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func sendWithRetries(_ request: URLRequest, repeatable: Bool) async throws -> Data {
        var attempt = 1
        while true {
            do {
                return try await sendOnce(request)
            } catch let failure as RequestFailure {
                let mayRetry = failure.isTransient && (repeatable || failure.neverSent)
                guard mayRetry, attempt < retry.attempts, (try? await Task.sleep(for: retry.delay)) != nil else {
                    throw failure.error
                }
                attempt += 1
            }
        }
    }

    private func sendOnce(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw RequestFailure(error: error, isTransient: error.isTransient, neverSent: false)
        } catch let error as URLError {
            throw RequestFailure(
                error: .transport(error.localizedDescription),
                isTransient: error.code != .cancelled,
                neverSent: Self.neverSentCodes.contains(error.code)
            )
        } catch {
            throw RequestFailure(error: .transport(error.localizedDescription), isTransient: false, neverSent: false)
        }
        do {
            try validate(response, data: data)
        } catch let error as APIError {
            throw RequestFailure(error: error, isTransient: error.isTransient, neverSent: false)
        }
        return data
    }

    /// Failures that happen before any bytes leave this Mac.
    private static let neverSentCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed
    ]

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
            request.httpBody = try Self.makeEncoder().encode(body)
        }
        return request
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

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

private struct RequestFailure: Error {
    let error: APIError
    let isTransient: Bool
    let neverSent: Bool
}

private struct ErrorBody: Decodable {
    let error: String
}
