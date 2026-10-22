import Foundation
import Testing
@testable import SimpleLoginKit

@Suite struct AccountAPITests {
    @Test func statsReadsTheAliasCount() async throws {
        let stub = StubTransport()
        stub.enqueue(status: 200, json: #"{"nb_alias": 12, "nb_block": 3, "nb_forward": 40, "nb_reply": 2}"#)
        let api = SimpleLoginAPI(apiKey: "secret", transport: stub)

        let stats = try await api.stats()

        #expect(stats.nbAlias == 12)
        #expect(stub.requests[0].httpMethod == "GET")
        #expect(stub.requests[0].url?.path == "/api/stats")
    }
}
