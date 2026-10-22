import Foundation

public protocol AliasAPI: Sendable {
    func alias(id: Int) async throws -> Alias
    func toggle(aliasID: Int) async throws -> Bool
}

extension SimpleLoginAPI: AliasAPI {
    public func aliases(page: Int, filter: AliasFilter? = nil, query: String? = nil) async throws -> [Alias] {
        var queryItems = [URLQueryItem(name: "page_id", value: String(page))]
        if let filter {
            queryItems.append(URLQueryItem(name: filter.rawValue, value: nil))
        }
        let response: AliasPage
        if let query, !query.isEmpty {
            response = try await send("POST", "/api/v2/aliases", query: queryItems, body: AliasSearchBody(query: query))
        } else {
            response = try await send("GET", "/api/v2/aliases", query: queryItems)
        }
        return response.aliases
    }

    public func alias(id: Int) async throws -> Alias {
        try await send("GET", "/api/aliases/\(id)")
    }

    public func toggle(aliasID: Int) async throws -> Bool {
        let response: ToggleResponse = try await send("POST", "/api/aliases/\(aliasID)/toggle", repeatable: false)
        return response.enabled
    }

    public func setPinned(_ pinned: Bool, aliasID: Int) async throws {
        let _: IgnoredResponse = try await send("PATCH", "/api/aliases/\(aliasID)", body: PinnedBody(pinned: pinned))
    }

    public func createRandomAlias() async throws -> Alias {
        try await send("POST", "/api/alias/random/new", body: EmptyBody(), repeatable: false)
    }

    public func aliasOptions() async throws -> AliasOptions {
        try await send("GET", "/api/v5/alias/options")
    }

    public func mailboxes() async throws -> [Mailbox] {
        let response: MailboxList = try await send("GET", "/api/v2/mailboxes")
        return response.mailboxes
    }

    public func createCustomAlias(prefix: String, signedSuffix: String, mailboxIDs: [Int]) async throws -> Alias {
        let body = CustomAliasBody(aliasPrefix: prefix, signedSuffix: signedSuffix, mailboxIds: mailboxIDs)
        return try await send("POST", "/api/v3/alias/custom/new", body: body, repeatable: false)
    }
}

private struct AliasPage: Decodable {
    let aliases: [Alias]
}

private struct MailboxList: Decodable {
    let mailboxes: [Mailbox]
}

private struct ToggleResponse: Decodable {
    let enabled: Bool
}

private struct IgnoredResponse: Decodable {}

private struct EmptyBody: Encodable {}

private struct AliasSearchBody: Encodable {
    let query: String
}

private struct PinnedBody: Encodable {
    let pinned: Bool
}

private struct CustomAliasBody: Encodable {
    let aliasPrefix: String
    let signedSuffix: String
    let mailboxIds: [Int]
}
