#if DEBUG
import Foundation
import SimpleLoginKit

/// Answers the SimpleLogin API requests the app makes from the sample account, keeping changes in memory.
actor DemoTransport: HTTPTransport {
    private static let pageSize = 20

    private var aliases = DemoAccount.aliases
    private var nextAliasID = 200

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(150))
        let url = request.url!
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        guard let json = try answer(request.httpMethod ?? "GET", url.path, url: url, body: body) else {
            return try response(status: 404, json: ["error": "Not available in demo mode"], for: url)
        }
        return try response(status: 200, json: json, for: url)
    }

    private func answer(_ method: String, _ path: String, url: URL, body: [String: Any]) throws -> Any? {
        if let match = path.wholeMatch(of: /\/api\/aliases\/(\d+)\/toggle/), method == "POST" {
            let index = try index(of: match.1)
            aliases[index].enabled.toggle()
            return ["enabled": aliases[index].enabled]
        }
        if let match = path.wholeMatch(of: /\/api\/aliases\/(\d+)/) {
            let index = try index(of: match.1)
            if method == "PATCH" {
                aliases[index].pinned = body["pinned"] as? Bool ?? aliases[index].pinned
                return ["ok": true]
            }
            return aliasJSON(aliases[index])
        }
        switch (method, path) {
        case ("GET", "/api/stats"):
            return ["nb_alias": aliases.count, "nb_block": 0, "nb_forward": 0, "nb_reply": 0]
        case ("GET", "/api/user_info"):
            return ["name": DemoAccount.name, "email": DemoAccount.email, "is_premium": true, "in_trial": false]
        case (_, "/api/v2/aliases"):
            return ["aliases": page(of: url, query: body["query"] as? String).map(aliasJSON)]
        case ("POST", "/api/alias/random/new"):
            let name = DemoAccount.randomAliasNames[nextAliasID % DemoAccount.randomAliasNames.count]
            return aliasJSON(addAlias(email: "\(name)@example.com"))
        case ("GET", "/api/v5/alias/options"):
            return [
                "can_create": true,
                "prefix_suggestion": "",
                "suffixes": DemoAccount.suffixes.map { ["suffix": $0.suffix, "signed_suffix": $0.suffix, "is_custom": $0.isCustom, "is_premium": false] },
            ]
        case ("GET", "/api/v2/mailboxes"):
            return ["mailboxes": [["id": 1, "email": DemoAccount.email, "default": true, "verified": true, "nb_alias": aliases.count]]]
        case ("POST", "/api/v3/alias/custom/new"):
            let prefix = body["alias_prefix"] as? String ?? ""
            let suffix = body["signed_suffix"] as? String ?? ""
            return aliasJSON(addAlias(email: prefix + suffix))
        default:
            return nil
        }
    }

    private func page(of url: URL, query: String?) -> ArraySlice<DemoAccount.Alias> {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pageID = items.first { $0.name == "page_id" }?.value.flatMap(Int.init) ?? 0
        var matching = aliases
        if items.contains(where: { $0.name == "pinned" }) { matching = matching.filter(\.pinned) }
        if let query, !query.isEmpty { matching = matching.filter { $0.email.localizedCaseInsensitiveContains(query) } }
        let start = min(pageID * Self.pageSize, matching.count)
        return matching[start..<min(start + Self.pageSize, matching.count)]
    }

    private func index(of id: Substring) throws -> Int {
        guard let index = aliases.firstIndex(where: { String($0.id) == id }) else { throw URLError(.fileDoesNotExist) }
        return index
    }

    private func addAlias(email: String) -> DemoAccount.Alias {
        nextAliasID += 1
        let alias = DemoAccount.Alias(id: nextAliasID, email: email, enabled: true, pinned: false)
        aliases.insert(alias, at: 0)
        return alias
    }

    private func aliasJSON(_ alias: DemoAccount.Alias) -> [String: Any] {
        [
            "id": alias.id,
            "email": alias.email,
            "name": NSNull(),
            "enabled": alias.enabled,
            "note": alias.note ?? NSNull(),
            "pinned": alias.pinned,
            "nb_block": alias.blocked,
            "nb_forward": alias.forwarded,
            "nb_reply": 0,
            "creation_timestamp": 1_760_000_000,
            "mailbox": ["id": 1, "email": DemoAccount.email],
            "mailboxes": [["id": 1, "email": DemoAccount.email]],
            "latest_activity": NSNull(),
        ]
    }

    private func response(status: Int, json: Any, for url: URL) throws -> (Data, HTTPURLResponse) {
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }
}
#endif
