import Foundation
import SimpleLoginKit

/// Finds aliases for the alias picker of an action: what to suggest, what a search matches, and what a chosen ID resolves to.
@MainActor
struct AliasLookup {
    private let appModel: AppModel
    private let sleep: @MainActor (Duration) async throws -> Void

    private static let searchDelay: Duration = .milliseconds(300)

    init(appModel: AppModel, sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.appModel = appModel
        self.sleep = sleep
    }

    func suggestions() async throws -> [Alias] {
        let api = try signedInAPI()
        if appModel.pinnedLoaded {
            return appModel.pinned
        }
        return try await api.aliases(page: 0, filter: .pinned)
    }

    func search(_ text: String) async throws -> [Alias] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return try await suggestions()
        }
        let api = try signedInAPI()
        try await sleep(Self.searchDelay)
        try Task.checkCancellation()
        return try await api.aliases(page: 0, query: text)
    }

    /// The aliases for the given IDs in the same order, without those that no longer exist.
    func aliases(ids: [Int]) async throws -> [Alias] {
        let api = try signedInAPI()
        let pinned = Dictionary(appModel.pinned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var resolved: [Alias] = []
        for id in ids {
            if let alias = pinned[id] {
                resolved.append(alias)
                continue
            }
            do {
                resolved.append(try await api.alias(id: id))
            } catch where APIError.meansAliasIsGone(error) {
                continue
            }
        }
        return resolved
    }

    private func signedInAPI() throws -> SimpleLoginAPI {
        guard let api = appModel.api else { throw TimerEngineError.notSignedIn }
        return api
    }
}
