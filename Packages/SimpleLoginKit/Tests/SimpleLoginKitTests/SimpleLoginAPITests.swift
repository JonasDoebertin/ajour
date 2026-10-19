import Foundation
import Testing
@testable import SimpleLoginKit

@Suite struct SimpleLoginAPITests {
    @Test func userInfoSendsAuthHeaderAndDecodes() async throws {
        let stub = StubTransport()
        stub.enqueue(status: 200, json: #"{"name":"Jonas","email":"j@example.com","is_premium":true,"in_trial":false,"max_alias_free_plan":5}"#)
        let api = SimpleLoginAPI(apiKey: "secret", transport: stub)
        let info = try await api.userInfo()
        #expect(info == UserInfo(name: "Jonas", email: "j@example.com", isPremium: true))
        #expect(stub.requests[0].url?.absoluteString == "https://app.simplelogin.io/api/user_info")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authentication") == "secret")
    }

    @Test func status401MapsToUnauthorized() async {
        let stub = StubTransport(); stub.enqueue(status: 401, json: #"{"error":"Wrong api key"}"#)
        await #expect(throws: APIError.unauthorized) { try await SimpleLoginAPI(apiKey: "x", transport: stub).userInfo() }
    }

    @Test func errorBodyIsSurfaced() async {
        let stub = StubTransport(); stub.enqueue(status: 400, json: #"{"error":"Alias quota exceeded"}"#)
        await #expect(throws: APIError.server(status: 400, message: "Alias quota exceeded")) { try await SimpleLoginAPI(apiKey: "x", transport: stub).userInfo() }
    }

    @Test func transportFailureMapsToTransportError() async {
        let stub = StubTransport() // empty queue throws URLError
        await #expect { try await SimpleLoginAPI(apiKey: "x", transport: stub).userInfo() } throws: { error in
            if case APIError.transport = error { return true } else { return false }
        }
    }
}
