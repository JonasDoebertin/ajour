import AppKit
import Foundation
import Observation
import SimpleLoginKit

struct AliasSection: Identifiable, Equatable {
    let title: String
    let aliases: [Alias]
    var id: String { title }
}

enum EmptyState: Equatable {
    case noAliases
    case noMatches(query: String)
}

/// Lists every alias of the account page by page, optionally filtered by a search, and acts on single rows.
@MainActor @Observable final class AllAliasesModel {
    var searchText = ""
    private(set) var aliases: [Alias] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The number of aliases in the account, or nil until `GET /api/stats` has answered.
    private(set) var totalAliases: Int?
    /// False until the current list's first page has answered, so it isn't called empty before.
    private var hasLoadedFirstPage = false
    private var query = ""
    private var nextPage = 0
    private var hasMorePages = true
    /// The app's enabled changes up to here are already reflected in the loaded rows.
    private var listStartSequence = 0
    /// Changes whenever the list starts over, so a page that arrives for an older list is dropped.
    @ObservationIgnored private var generation = 0
    /// Changes on every reload, so a total that arrives for an older reload is dropped.
    @ObservationIgnored private var totalGeneration = 0
    @ObservationIgnored private var pendingSearch: Task<Void, Never>?

    /// Opens the window where the API key is replaced; set once the windows exist.
    @ObservationIgnored var onReplaceAPIKey: () -> Void = {}

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
        totalGeneration += 1
        totalAliases = nil
        async let total: Void = loadTotal()
        await startOver(query: searchText)
        await total
    }

    private func loadTotal() async {
        let generation = totalGeneration
        guard let stats = try? await appModel.api?.stats(), generation == totalGeneration else { return }
        totalAliases = stats.nbAlias
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
            hasLoadedFirstPage = true
            let listedIDs = Set(aliases.map(\.id))
            aliases += page.filter { !listedIDs.contains($0.id) }
            nextPage += 1
            hasMorePages = page.count == Self.pageSize
            errorMessage = nil
        case .failure(let error):
            errorMessage = AppModel.userMessage(for: error)
        }
    }

    /// A running timer, or a change the app made after the row loaded, wins over the row's enabled flag.
    func state(of alias: Alias) -> AliasMenuState {
        if let record = appModel.engine.record(for: alias.id) {
            return MenuSections.state(of: record, failure: appModel.engine.failures[alias.id], now: appModel.now)
        }
        let enabled = appModel.knownEnabled(aliasID: alias.id, since: listStartSequence) ?? alias.enabled
        return enabled ? .enabled : .disabled
    }

    func status(of alias: Alias) -> AliasStatus {
        AliasStatus.make(
            state: state(of: alias),
            activity: appModel.activity(aliasID: alias.id),
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    func accessibilityLabel(for alias: Alias) -> String {
        AliasStatus.accessibilityLabel(
            email: alias.email,
            pinned: alias.pinned,
            state: state(of: alias),
            activity: appModel.activity(aliasID: alias.id)
        )
    }

    var sections: [AliasSection] {
        [
            AliasSection(title: "Pinned", aliases: aliases.filter(\.pinned)),
            AliasSection(title: "Other Aliases", aliases: aliases.filter { !$0.pinned }),
        ].filter { !$0.aliases.isEmpty }
    }

    /// Empty while nothing has answered yet, so a loading window doesn't claim the account has no aliases.
    var subtitle: String {
        guard hasLoadedFirstPage || totalAliases != nil else { return "" }
        if !query.isEmpty, hasLoadedFirstPage {
            guard let totalAliases else {
                return aliases.count == 1 ? "1 matching alias" : "\(aliases.count) matching aliases"
            }
            return "\(aliases.count) of \(Self.count(totalAliases))"
        }
        let total = totalAliases ?? aliases.count
        if isLoading, hasLoadedFirstPage {
            return "\(Self.count(aliases.count)) loaded · loading more"
        }
        let timers = appModel.engine.records.count
        switch timers {
        case 0: return Self.count(total)
        case 1: return "\(Self.count(total)) · 1 timer running"
        default: return "\(Self.count(total)) · \(timers) timers running"
        }
    }

    private static func count(_ aliases: Int) -> String {
        aliases == 1 ? "1 alias" : "\(aliases) aliases"
    }

    var emptyState: EmptyState? {
        guard hasLoadedFirstPage, aliases.isEmpty, errorMessage == nil else { return nil }
        return query.isEmpty ? .noAliases : .noMatches(query: query)
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

    /// Enables a disabled alias for a while or extends a running timer.
    /// Rows show the new state through `state(of:)`, like after any other change the app makes.
    func enable(_ alias: Alias, for duration: AliasDuration) async {
        await appModel.enable(aliasID: alias.id, for: duration)
    }

    func disableAfter(_ alias: Alias, duration: AliasDuration) async {
        await appModel.disableAfter(aliasID: alias.id, duration: duration)
    }

    func enablePermanently(_ alias: Alias) async {
        await appModel.enablePermanently(aliasID: alias.id)
    }

    func keepEnabled(_ alias: Alias) async {
        await appModel.keepEnabled(aliasID: alias.id, email: alias.email)
    }

    func retryDisable(_ alias: Alias) async {
        await appModel.retryDisable(aliasID: alias.id)
    }

    func disable(_ alias: Alias) async {
        await appModel.disableNow(aliasID: alias.id)
    }

    private func startOver(query: String) async {
        generation += 1
        listStartSequence = appModel.enabledChangeSequence
        hasLoadedFirstPage = false
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
