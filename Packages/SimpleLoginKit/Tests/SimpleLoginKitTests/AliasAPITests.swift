import Foundation
import Testing
@testable import SimpleLoginKit

@Suite struct AliasAPITests {
    private func makeAPI(status: Int = 200, json: String) -> (SimpleLoginAPI, StubTransport) {
        let stub = StubTransport()
        stub.enqueue(status: status, json: json)
        return (SimpleLoginAPI(apiKey: "secret", transport: stub), stub)
    }

    private func bodyJSON(of request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func components(of request: URLRequest) throws -> URLComponents {
        let url = try #require(request.url)
        return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    @Test func aliasesPinnedPageUsesGetWithFilter() async throws {
        let (api, stub) = makeAPI(json: #"{"aliases":[\#(Fixtures.aliasJSON)]}"#)
        let aliases = try await api.aliases(page: 0, filter: .pinned)
        let request = stub.requests[0]
        let components = try components(of: request)
        #expect(request.httpMethod == "GET")
        #expect(components.path == "/api/v2/aliases")
        #expect(components.queryItems?.first { $0.name == "page_id" }?.value == "0")
        #expect(components.queryItems?.contains { $0.name == "pinned" } == true)
        #expect(request.httpBody == nil)
        #expect(aliases.count == 1)
        #expect(aliases[0].id == 7)
        #expect(aliases[0].nbBlock == 3)
        #expect(aliases[0].mailboxes == [MailboxRef(id: 1, email: "a@b.c")])
        #expect(aliases[0].latestActivity?.action == .forward)
        #expect(aliases[0].latestActivity?.timestamp == Date(timeIntervalSince1970: 1586195834))
        #expect(aliases[0].latestActivity?.contact == AliasContact(email: "login@shop.com", name: nil))
    }

    @Test func aliasesWithoutFilterOmitsFilterQueryItems() async throws {
        let (api, stub) = makeAPI(json: #"{"aliases":[]}"#)
        _ = try await api.aliases(page: 2)
        let names = try components(of: stub.requests[0]).queryItems?.map(\.name)
        #expect(names == ["page_id"])
    }

    @Test func aliasesWithQueryUsesPostBody() async throws {
        let (api, stub) = makeAPI(json: #"{"aliases":[]}"#)
        _ = try await api.aliases(page: 1, filter: nil, query: "shop")
        let request = stub.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v2/aliases")
        #expect(request.url?.query == "page_id=1")
        #expect(try bodyJSON(of: request) as? [String: String] == ["query": "shop"])
    }

    @Test func aliasFetchesSingleAlias() async throws {
        let (api, stub) = makeAPI(json: Fixtures.aliasJSON)
        let alias = try await api.alias(id: 7)
        #expect(stub.requests[0].httpMethod == "GET")
        #expect(stub.requests[0].url?.path == "/api/aliases/7")
        #expect(alias.email == "shop@example.com")
    }

    @Test func toggleReturnsNewState() async throws {
        let (api, stub) = makeAPI(json: #"{"enabled":false}"#)
        let enabled = try await api.toggle(aliasID: 7)
        #expect(enabled == false)
        #expect(stub.requests[0].httpMethod == "POST")
        #expect(stub.requests[0].url?.path == "/api/aliases/7/toggle")
    }

    @Test func setPinnedSendsPatch() async throws {
        let (api, stub) = makeAPI(json: #"{"ok":true}"#)
        try await api.setPinned(true, aliasID: 7)
        let request = stub.requests[0]
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/api/aliases/7")
        #expect(try bodyJSON(of: request) as? [String: Bool] == ["pinned": true])
    }

    @Test func createRandomAliasPostsEmptyBody() async throws {
        let (api, stub) = makeAPI(json: Fixtures.aliasJSON)
        let alias = try await api.createRandomAlias()
        let request = stub.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/alias/random/new")
        #expect(try bodyJSON(of: request).isEmpty)
        #expect(alias.id == 7)
    }

    @Test func customAliasSendsSignedSuffixAndMailboxes() async throws {
        let (api, stub) = makeAPI(json: Fixtures.aliasJSON)
        _ = try await api.createCustomAlias(prefix: "shop", signedSuffix: "@my.dev.X", mailboxIDs: [1, 2])
        let request = stub.requests[0]
        let body = try bodyJSON(of: request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v3/alias/custom/new")
        #expect(Set(body.keys) == ["alias_prefix", "signed_suffix", "mailbox_ids"])
        #expect(body["alias_prefix"] as? String == "shop")
        #expect(body["signed_suffix"] as? String == "@my.dev.X")
        #expect(body["mailbox_ids"] as? [Int] == [1, 2])
    }

    @Test func aliasOptionsDecodesSuffixes() async throws {
        let (api, stub) = makeAPI(json: #"{"can_create":true,"prefix_suggestion":"","suffixes":[{"suffix":"@my.dev","signed_suffix":"@my.dev.X","is_custom":true,"is_premium":false}]}"#)
        let options = try await api.aliasOptions()
        #expect(stub.requests[0].httpMethod == "GET")
        #expect(stub.requests[0].url?.path == "/api/v5/alias/options")
        #expect(options.canCreate)
        #expect(options.suffixes == [AliasSuffix(suffix: "@my.dev", signedSuffix: "@my.dev.X", isCustom: true, isPremium: false)])
    }

    @Test func mailboxesDecodesDefaultFlag() async throws {
        let (api, stub) = makeAPI(json: Fixtures.mailboxesJSON)
        let mailboxes = try await api.mailboxes()
        #expect(stub.requests[0].url?.path == "/api/v2/mailboxes")
        #expect(mailboxes.count == 2)
        #expect(mailboxes[0] == Mailbox(id: 1, email: "a@b.c", isDefault: true))
        #expect(mailboxes[1].isDefault == false)
    }

    @Test func unknownActivityActionDecodesAsOther() async throws {
        let json = Fixtures.aliasJSON.replacingOccurrences(of: "\"forward\"", with: "\"something_new\"")
        let (api, _) = makeAPI(json: json)
        let alias = try await api.alias(id: 7)
        #expect(alias.latestActivity?.action == .other)
    }

    @Test func aliasWithoutLatestActivityDecodes() async throws {
        let json = Fixtures.aliasJSON.replacingOccurrences(of: "\"latest_activity\":", with: "\"unused\":")
        let (api, _) = makeAPI(json: json)
        let alias = try await api.alias(id: 7)
        #expect(alias.latestActivity == nil)
    }
}
