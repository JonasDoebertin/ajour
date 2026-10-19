import Foundation
import Observation
import SimpleLoginKit

/// Lists every alias of the account page by page, optionally filtered by a search, and acts on single rows.
@MainActor @Observable final class AllAliasesModel {
    var searchText = ""
    private(set) var aliases: [Alias] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var query = ""
    private var nextPage = 0
    private var hasMorePages = true
    /// Changes whenever the list starts over, so a page that arrives for an older list is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingSearch: Task<Void, Never>?

    @ObservationIgnored private let appModel: AppModel
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    private static let searchDelay: Duration = .milliseconds(300)
    private static let pageSize = 20

    init(appModel: AppModel, sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.appModel = appModel
        self.sleep = sleep
    }

    /// Starts the list over for the current search text.
    func reload() async {
        pendingSearch?.cancel()
        await startOver(query: searchText)
    }

    /// Searches once typing pauses, so not every keystroke sends a request.
    @discardableResult
    func scheduleSearch() -> Task<Void, Never> {
        pendingSearch?.cancel()
        let query = searchText
        let search = Task {
            do {
                try await sleep(Self.searchDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await startOver(query: query)
        }
        pendingSearch = search
        return search
    }

    /// Called when a row appears; the last row loads the next page.
    func loadMore(after alias: Alias) async {
        guard alias.id == aliases.last?.id else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading, hasMorePages else { return }
        guard let api = appModel.api else {
            errorMessage = AppModel.userMessage(for: TimerEngineError.notSignedIn)
            return
        }
        let generation = self.generation
        isLoading = true
        let result: Result<[Alias], any Error>
        do {
            result = .success(try await api.aliases(page: nextPage, query: query.isEmpty ? nil : query))
        } catch {
            result = .failure(error)
        }
        guard generation == self.generation else { return }
        isLoading = false
        switch result {
        case .success(let page):
            let listedIDs = Set(aliases.map(\.id))
            aliases += page.filter { !listedIDs.contains($0.id) }
            nextPage += 1
            hasMorePages = page.count == Self.pageSize
            errorMessage = nil
        case .failure(let error):
            errorMessage = AppModel.userMessage(for: error)
        }
    }

    /// A running timer wins over the row's enabled flag, which may be older.
    func state(of alias: Alias) -> AliasMenuState {
        if let record = appModel.engine.record(for: alias.id) {
            return .timed(remaining: max(0, record.expiresAt.timeIntervalSince(appModel.now)))
        }
        return alias.enabled ? .enabled : .disabled
    }

    func stateLabel(for alias: Alias) -> String {
        switch state(of: alias) {
        case .disabled: "Disabled"
        case .enabled: "Enabled"
        case .timed(let remaining): "\(RemainingTime.format(remaining)) left"
        }
    }

    func isBusy(_ alias: Alias) -> Bool {
        appModel.isBusy(aliasID: alias.id)
    }

    func togglePin(_ alias: Alias) async {
        let isPinned = !alias.pinned
        guard await appModel.setPinned(isPinned, alias: alias) else { return }
        updateRow(aliasID: alias.id) { $0.settingPinned(isPinned) }
    }

    func copy(_ alias: Alias) {
        appModel.copy(email: alias.email)
    }

    /// Enables a disabled alias for a while, extends a running timer, or times an enabled alias.
    func enable(_ alias: Alias, for duration: AliasDuration) async {
        guard await appModel.enable(aliasID: alias.id, for: duration) else { return }
        updateRow(aliasID: alias.id) { $0.settingEnabled(true) }
    }

    func enablePermanently(_ alias: Alias) async {
        guard await appModel.enablePermanently(aliasID: alias.id) else { return }
        updateRow(aliasID: alias.id) { $0.settingEnabled(true) }
    }

    func disable(_ alias: Alias) async {
        guard await appModel.disableNow(aliasID: alias.id) else { return }
        updateRow(aliasID: alias.id) { $0.settingEnabled(false) }
    }

    private func startOver(query: String) async {
        generation += 1
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        aliases = []
        nextPage = 0
        hasMorePages = true
        isLoading = false
        errorMessage = nil
        await loadNextPage()
    }

    private func updateRow(aliasID: Int, _ change: (Alias) -> Alias) {
        guard let index = aliases.firstIndex(where: { $0.id == aliasID }) else { return }
        aliases[index] = change(aliases[index])
    }
}
