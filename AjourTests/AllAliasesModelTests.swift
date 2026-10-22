import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

/// The "All Aliases" window: paging, searching, row states, and row actions.
@MainActor
final class AllAliasesModelTests {
    let transport = StubTransport()
    let clock = TestClock()
    let timerStore: InMemoryTimerStore
    private(set) var copied: [String] = []
    private(set) var searchDelays: [Duration] = []

    init(records: [TimerRecord] = []) {
        timerStore = InMemoryTimerStore(records: records)
    }

    func signedInAppModel() async throws -> AppModel {
        let clock = clock
        let appModel = AppModel(
            keyStore: InMemoryAPIKeyStore(),
            timerStore: timerStore,
            transport: transport,
            now: { clock.now },
            copyToClipboard: { [weak self] in self?.copied.append($0) },
            retry: .once
        )
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await appModel.signIn(apiKey: "valid-key")
        return appModel
    }

    func makeModel(appModel: AppModel) -> AllAliasesModel {
        AllAliasesModel(appModel: appModel) { [weak self] delay in self?.searchDelays.append(delay) }
    }

    /// A window that has loaded the given aliases as its first page.
    func loadedModel(_ aliases: [String], total: Int? = nil) async throws -> (AllAliasesModel, AppModel) {
        let appModel = try await signedInAppModel()
        let model = makeModel(appModel: appModel)
        if let total {
            transport.enqueue("/api/stats", json: #"{"nb_alias":\#(total)}"#)
        }
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON(aliases))
        await model.reload()
        return (model, appModel)
    }

    static func pageJSON(_ aliases: [String]) -> String {
        #"{"aliases":[\#(aliases.joined(separator: ","))]}"#
    }

    func pageRequests(method: String = "GET") -> [URLRequest] {
        transport.requests.filter { $0.url?.path == "/api/v2/aliases" && $0.httpMethod == method }
    }

    func pageIDs(method: String = "GET") -> [String?] {
        pageRequests(method: method).map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page_id" }?.value
        }
    }

    func searchedQueries() throws -> [String?] {
        try pageRequests(method: "POST").map { request in
            let body = try #require(request.httpBody)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])["query"] as? String
        }
    }

    func requestCount(path: String) -> Int {
        transport.requests.filter { $0.url?.path == path }.count
    }

    // MARK: Paging

    @Test func openingShowsTheFirstPageOfAllAliases() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1), Fixtures.aliasJSON(id: 2)])

        #expect(model.aliases.map(\.id) == [1, 2])
        #expect(pageIDs() == ["0"])
        let queryItems = URLComponents(url: try #require(pageRequests().first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.map(\.name) == ["page_id"])
        #expect(model.errorMessage == nil)
    }

    @Test func reachingTheLastRowLoadsTheNextPage() async throws {
        let firstPage = (1...20).map { Fixtures.aliasJSON(id: $0) }
        let (model, _) = try await loadedModel(firstPage)
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 21...22))

        await model.loadMore(after: try #require(model.aliases.last))

        #expect(model.aliases.map(\.id) == Array(1...22))
        #expect(pageIDs() == ["0", "1"])
    }

    @Test func aRowBeforeTheLastLoadsNothing() async throws {
        let (model, _) = try await loadedModel((1...20).map { Fixtures.aliasJSON(id: $0) })

        await model.loadMore(after: try #require(model.aliases.first))

        #expect(pageIDs() == ["0"])
    }

    @Test func aPageWithFewerThanTwentyAliasesEndsTheList() async throws {
        let (model, _) = try await loadedModel((1...19).map { Fixtures.aliasJSON(id: $0) })

        await model.loadMore(after: try #require(model.aliases.last))

        #expect(pageIDs() == ["0"])
    }

    @Test func aPageThatIsStillLoadingIsNotRequestedAgain() async throws {
        let (model, _) = try await loadedModel((1...20).map { Fixtures.aliasJSON(id: $0) })
        let lastRow = try #require(model.aliases.last)
        transport.holdNext("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 21...22))
        let loading = Task { await model.loadMore(after: lastRow) }
        await transport.waitUntilARequestIsHeld()

        await model.loadMore(after: lastRow)
        transport.release()
        await loading.value

        #expect(pageIDs() == ["0", "1"])
        #expect(model.aliases.map(\.id) == Array(1...22))
    }

    @Test func anAliasRepeatedOnTheNextPageIsListedOnce() async throws {
        let (model, _) = try await loadedModel((1...20).map { Fixtures.aliasJSON(id: $0) })
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 20...21))

        await model.loadMore(after: try #require(model.aliases.last))

        #expect(model.aliases.map(\.id) == Array(1...21))
    }

    @Test func aPageThatFailedShowsWhyAndCanBeLoadedAgain() async throws {
        let appModel = try await signedInAppModel()
        let model = makeModel(appModel: appModel)
        await model.reload()
        #expect(model.errorMessage == "Could not reach SimpleLogin. Check your network connection.")
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...2))

        await model.loadNextPage()

        #expect(model.aliases.map(\.id) == [1, 2])
        #expect(model.errorMessage == nil)
        #expect(pageIDs() == ["0", "0"])
    }

    @Test func openingWhileSignedOutExplainsThatSetupIsMissing() async {
        let appModel = AppModel(keyStore: InMemoryAPIKeyStore(), timerStore: timerStore, transport: transport, retry: .once)
        appModel.start()
        let model = makeModel(appModel: appModel)

        await model.reload()

        #expect(model.errorMessage == "Not signed in. Set up your API key first.")
        #expect(transport.requests.isEmpty)
    }

    @Test func aNewWindowDoesNotClaimThereAreNoAliasesBeforeLoading() async throws {
        let model = makeModel(appModel: try await signedInAppModel())

        #expect(model.emptyState == nil)
    }

    @Test func anEmptyAccountSaysThereAreNoAliases() async throws {
        let (model, _) = try await loadedModel([])

        #expect(model.emptyState == .noAliases)
    }

    @Test func aSearchThatIsStillLoadingDoesNotClaimThereAreNoMatches() async throws {
        let (model, _) = try await loadedModel([])
        transport.holdNext("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 5...5))
        model.searchText = "shop"
        let search = model.scheduleSearch()
        await transport.waitUntilARequestIsHeld()

        #expect(model.emptyState == nil)
        transport.release()
        await search.value
    }

    // MARK: Search

    @Test func searchingWaitsBrieflyThenSearchesForTheQuery() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)])
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 5...6))
        model.searchText = " shop "

        await model.scheduleSearch().value

        #expect(searchDelays == [.milliseconds(300)])
        #expect(try searchedQueries() == ["shop"])
        #expect(pageIDs(method: "POST") == ["0"])
        #expect(model.aliases.map(\.id) == [5, 6])
    }

    @Test func aNewQueryStartsTheListAndPagingOver() async throws {
        let (model, _) = try await loadedModel((1...20).map { Fixtures.aliasJSON(id: $0) })
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 21...40))
        await model.loadMore(after: try #require(model.aliases.last))
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 100...119))
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 120...121))
        model.searchText = "shop"

        await model.scheduleSearch().value
        await model.loadMore(after: try #require(model.aliases.last))

        #expect(model.aliases.map(\.id) == Array(100...121))
        #expect(pageIDs(method: "POST") == ["0", "1"])
        #expect(try searchedQueries() == ["shop", "shop"])
    }

    @Test func clearingTheSearchListsAllAliasesAgain() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)])
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 5...5))
        model.searchText = "shop"
        await model.scheduleSearch().value
        transport.enqueue("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 1...2))
        model.searchText = ""

        await model.scheduleSearch().value

        #expect(model.aliases.map(\.id) == [1, 2])
        #expect(pageIDs() == ["0", "0"])
    }

    @Test func typingQuicklySearchesOnlyForTheLatestText() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)])
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 5...5))
        model.searchText = "s"
        let firstSearch = model.scheduleSearch()
        model.searchText = "sh"

        let secondSearch = model.scheduleSearch()
        await firstSearch.value
        await secondSearch.value

        #expect(try searchedQueries() == ["sh"])
        #expect(model.aliases.map(\.id) == [5])
    }

    @Test func resultsOfAnOlderQueryAreDiscarded() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)])
        transport.holdNext("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 5...5))
        model.searchText = "old"
        let olderSearch = model.scheduleSearch()
        await transport.waitUntilARequestIsHeld()
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 6...6))
        model.searchText = "new"

        await model.scheduleSearch().value
        transport.release()
        await olderSearch.value

        #expect(model.aliases.map(\.id) == [6])
        #expect(model.isLoading == false)
    }

    // MARK: Sections, subtitle, and empty state

    @Test func sectionsPutPinnedAliasesFirst() async throws {
        let (model, _) = try await loadedModel([
            Fixtures.aliasJSON(id: 1, pinned: true),
            Fixtures.aliasJSON(id: 2, pinned: false),
            Fixtures.aliasJSON(id: 3, pinned: true),
        ])

        #expect(model.sections.map(\.title) == ["Pinned", "Other Aliases"])
        #expect(model.sections.map { $0.aliases.map(\.id) } == [[1, 3], [2]])
    }

    @Test func sectionsLeaveOutEmptyGroups() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1, pinned: false)])

        #expect(model.sections.map(\.title) == ["Other Aliases"])
    }

    @Test(arguments: [(1, "12 aliases · 1 timer running"), (2, "12 aliases · 2 timers running")])
    func subtitleCountsAliasesAndTimers(timers: Int, subtitle: String) async throws {
        let records = (1...timers).map {
            TimerRecord(aliasID: $0, email: "a\($0)@example.com", enabledAt: clock.now, expiresAt: clock.now.addingTimeInterval(60))
        }
        let test = AllAliasesModelTests(records: records)
        let (model, _) = try await test.loadedModel([Fixtures.aliasJSON(id: 1)], total: 12)

        #expect(model.subtitle == subtitle)
    }

    @Test func aFailedStatsCallAfterASuccessfulOneLeavesNoTotal() async throws {
        let (model, _) = try await loadedModel((1...3).map { Fixtures.aliasJSON(id: $0) }, total: 500)
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON((1...3).map { Fixtures.aliasJSON(id: $0) }))

        await model.reload()

        #expect(model.totalAliases == nil)
        #expect(model.subtitle == "3 aliases")
    }

    @Test func aTotalThatArrivesForAnOlderReloadIsIgnored() async throws {
        let appModel = try await signedInAppModel()
        let model = makeModel(appModel: appModel)
        transport.holdNext("/api/stats", json: #"{"nb_alias":99}"#)
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON([Fixtures.aliasJSON(id: 1)]))
        let olderReload = Task { await model.reload() }
        await transport.waitUntilARequestIsHeld()
        transport.enqueue("/api/stats", json: #"{"nb_alias":7}"#)
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON([Fixtures.aliasJSON(id: 1)]))

        await model.reload()
        transport.release()
        await olderReload.value

        #expect(model.totalAliases == 7)
    }

    @Test func subtitleUsesTheSingularForOneAlias() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)], total: 1)

        #expect(model.subtitle == "1 alias")
    }

    @Test func subtitleFallsBackToLoadedCountWithoutStats() async throws {
        let (model, _) = try await loadedModel((1...3).map { Fixtures.aliasJSON(id: $0) })

        #expect(model.subtitle == "3 aliases")
        #expect(model.errorMessage == nil)
    }

    @Test func subtitleStaysEmptyUntilTheFirstPageOrTheTotalAnswers() async throws {
        let model = makeModel(appModel: try await signedInAppModel())
        transport.holdNext("/api/v2/aliases", json: Self.pageJSON([Fixtures.aliasJSON(id: 1)]))
        let loading = Task { await model.reload() }
        await transport.waitUntilARequestIsHeld()

        #expect(model.subtitle == "")
        transport.release()
        await loading.value
        #expect(model.subtitle == "1 alias")
    }

    @Test func subtitleShowsMatchesWhileSearching() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)], total: 12)
        transport.enqueue("/api/v2/aliases", method: "POST", json: Self.pageJSON([]))
        model.searchText = "concert"

        await model.scheduleSearch().value

        #expect(model.subtitle == "0 of 12 aliases")
        #expect(model.emptyState == .noMatches(query: "concert"))
    }

    @Test func aFailedFirstPageWithoutATotalLeavesTheSubtitleEmpty() async throws {
        let model = makeModel(appModel: try await signedInAppModel())

        await model.reload()

        #expect(model.errorMessage != nil)
        #expect(model.subtitle == "")
    }

    @Test func aFailedSearchDoesNotCountZeroMatches() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)], total: 12)
        model.searchText = "concert"

        await model.scheduleSearch().value

        #expect(model.errorMessage != nil)
        #expect(model.subtitle == "12 aliases")
    }

    @Test func subtitleCountsMatchesWhenTheTotalIsUnknown() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)])
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 5...7))
        model.searchText = "concert"

        await model.scheduleSearch().value

        #expect(model.subtitle == "3 matching aliases")
    }

    @Test func subtitleCountsOneMatchWhenTheTotalIsUnknown() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)])
        transport.enqueue("/api/v2/aliases", method: "POST", json: Fixtures.aliasPageJSON(ids: 5...5))
        model.searchText = "concert"

        await model.scheduleSearch().value

        #expect(model.subtitle == "1 matching alias")
    }

    @Test func subtitleShowsLoadingMore() async throws {
        let (model, _) = try await loadedModel((1...20).map { Fixtures.aliasJSON(id: $0) }, total: 45)
        transport.holdNext("/api/v2/aliases", json: Fixtures.aliasPageJSON(ids: 21...22))
        let lastRow = try #require(model.aliases.last)
        let loading = Task { await model.loadMore(after: lastRow) }
        await transport.waitUntilARequestIsHeld()

        #expect(model.subtitle == "20 aliases loaded · loading more")
        transport.release()
        await loading.value
    }

    @Test func searchSubtitleWaitsForResults() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1)], total: 12)
        transport.holdNext("/api/v2/aliases", method: "POST", json: Self.pageJSON([]))
        model.searchText = "concert"
        let search = model.scheduleSearch()
        await transport.waitUntilARequestIsHeld()

        #expect(model.subtitle == "12 aliases")
        transport.release()
        await search.value
    }

    @Test func aRowReadsItsPinnedStateAndStatusToVoiceOver() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1, email: "travel@example.com", enabled: true, pinned: true)])

        #expect(model.accessibilityLabel(for: try #require(model.aliases.first)) == "travel@example.com, pinned, enabled")
    }

    // MARK: Row state

    @Test func rowsShowWhetherAnAliasIsEnabled() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 1, enabled: false), Fixtures.aliasJSON(id: 2, enabled: true)])

        #expect(model.aliases.map { model.status(of: $0).words } == ["Disabled", "Enabled"])
    }

    @Test func aTimedRowShowsItsRemainingTime() async throws {
        let test = AllAliasesModelTests(records: [
            TimerRecord(aliasID: 2, email: "shop@example.com", enabledAt: clock.now, expiresAt: clock.now.addingTimeInterval(192)),
        ])
        let (model, _) = try await test.loadedModel([Fixtures.aliasJSON(id: 2, enabled: true)])

        #expect(model.aliases.map { model.status(of: $0).words } == ["3:12 left"])
    }

    @Test func aRowWhoseTimerExpiredShowsAsDisabledInTheWindowAndTheMenu() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: false, pinned: true)])
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON([Fixtures.aliasJSON(id: 7, enabled: false, pinned: true)]))
        await appModel.refreshPinned()
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        await model.enable(try #require(model.aliases.first), for: .fiveMinutes)
        clock.advance(by: 301)
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        for work in appModel.scheduleTick() { await work.value }

        #expect(appModel.engine.records.isEmpty)
        #expect(model.aliases.map { model.status(of: $0).words } == ["Disabled"])
        #expect(appModel.pinned.first?.enabled == false)
    }

    @Test func aRowDisabledFromANotificationShowsAsDisabled() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        await model.enable(try #require(model.aliases.first), for: .fiveMinutes)
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await appModel.disableNow(aliasID: 7)

        #expect(model.aliases.map { model.status(of: $0).words } == ["Disabled"])
    }

    @Test func reloadingShowsTheServersStateOverAnEarlierChangeByTheApp() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))
        await appModel.disableNow(aliasID: 7)
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON([Fixtures.aliasJSON(id: 7, enabled: true)]))

        await model.reload()

        #expect(model.aliases.map { model.status(of: $0).words } == ["Enabled"])
    }

    // MARK: Row actions

    @Test func pinningARowMarksItPinnedAndAddsItToTheMenu() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, pinned: false)])
        transport.enqueue("/api/aliases/7", method: "PATCH", json: "{}")
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON([Fixtures.aliasJSON(id: 7, pinned: true)]))

        await model.togglePin(try #require(model.aliases.first))

        #expect(model.aliases.first?.pinned == true)
        #expect(appModel.pinned.map(\.id) == [7])
    }

    @Test func unpinningARowMarksItUnpinned() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 7, pinned: true)])
        transport.enqueue("/api/aliases/7", method: "PATCH", json: "{}")
        transport.enqueue("/api/v2/aliases", json: Self.pageJSON([]))

        await model.togglePin(try #require(model.aliases.first))

        #expect(model.aliases.first?.pinned == false)
    }

    @Test func aRejectedPinLeavesTheRowUnchanged() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, pinned: false)])

        await model.togglePin(try #require(model.aliases.first))

        #expect(model.aliases.first?.pinned == false)
        #expect(appModel.lastError != nil)
    }

    @Test func enablingARowForAWhileShowsItsRemainingTimeAndPutsItInTheMenu() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: false, pinned: false)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false, pinned: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        await model.enable(try #require(model.aliases.first), for: .fiveMinutes)

        #expect(model.aliases.map { model.status(of: $0).words } == ["5:00 left"])
        #expect(appModel.menuSections.timedUnpinned.map(\.id) == [7])
    }

    @Test func disablingAnEnabledRowLaterShowsItsRemainingTime() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))

        await model.disableAfter(try #require(model.aliases.first), duration: .fiveMinutes)

        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(model.aliases.map { model.status(of: $0).words } == ["5:00 left"])
    }

    @Test func disablingARowLaterThatWasDisabledElsewhereNeverEnablesIt() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        await model.disableAfter(try #require(model.aliases.first), duration: .fiveMinutes)

        #expect(requestCount(path: "/api/aliases/7/toggle") == 0)
        #expect(appModel.engine.records.isEmpty)
        #expect(model.aliases.map { model.status(of: $0).words } == ["Disabled"])
        #expect(appModel.lastError == "shop@example.com is already disabled.")
    }

    @Test func enablingARowPermanentlyShowsItAsEnabledWithoutATimer() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))

        await model.enablePermanently(try #require(model.aliases.first))

        #expect(model.aliases.map { model.status(of: $0).words } == ["Enabled"])
        #expect(appModel.engine.records.isEmpty)
    }

    @Test func disablingARowShowsItAsDisabled() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: true)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: true))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.disable(try #require(model.aliases.first))

        #expect(requestCount(path: "/api/aliases/7/toggle") == 1)
        #expect(model.aliases.map { model.status(of: $0).words } == ["Disabled"])
    }

    @Test func aFailedDisableLeavesTheRowEnabled() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: true)])

        await model.disable(try #require(model.aliases.first))

        #expect(model.aliases.map { model.status(of: $0).words } == ["Enabled"])
        #expect(appModel.lastError == "Could not reach SimpleLogin. Check your network connection.")
    }

    @Test func keepingATimedRowEnabledStopsItsTimer() async throws {
        let (model, appModel) = try await loadedModel([Fixtures.aliasJSON(id: 7, enabled: false)])
        transport.enqueue("/api/aliases/7", json: Fixtures.aliasJSON(id: 7, enabled: false))
        transport.enqueue("/api/aliases/7/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: true))
        await model.enable(try #require(model.aliases.first), for: .fiveMinutes)

        await model.keepEnabled(try #require(model.aliases.first))

        #expect(appModel.engine.records.isEmpty)
        #expect(model.aliases.map { model.status(of: $0).words } == ["Enabled"])
        #expect(requestCount(path: "/api/aliases/7/toggle") == 1)
    }

    @Test func copyingARowPutsItsAddressOnTheClipboard() async throws {
        let (model, _) = try await loadedModel([Fixtures.aliasJSON(id: 7, email: "shop@example.com")])

        model.copy(try #require(model.aliases.first))

        #expect(copied == ["shop@example.com"])
    }
}
