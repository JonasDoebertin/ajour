import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

/// The "New Alias" window: offering suffixes, choosing the mailbox, and creating a custom alias.
@MainActor
final class NewAliasModelTests {
    let transport = StubTransport()
    let clock = TestClock()
    private(set) var copied: [String] = []
    private(set) var announced: [String] = []

    func signedInAppModel(timerStore: any TimerStore = InMemoryTimerStore()) async throws -> AppModel {
        let clock = clock
        let appModel = AppModel(
            keyStore: InMemoryAPIKeyStore(),
            timerStore: timerStore,
            transport: transport,
            now: { clock.now },
            copyToClipboard: { [weak self] in self?.copied.append($0) }
        )
        appModel.onNewAliasCopied = { [weak self] in self?.announced.append($0) }
        transport.enqueue("/api/user_info", json: Fixtures.userInfoJSON)
        _ = try await appModel.signIn(apiKey: "valid-key")
        return appModel
    }

    func enqueueChoices(
        canCreate: Bool = true,
        suffixes: [String] = [Fixtures.suffixJSON("@simplelogin.com", isCustom: false), Fixtures.suffixJSON("@my.dev", isCustom: true)],
        mailboxes: [String] = [Fixtures.mailboxJSON(id: 1, email: "a@b.c", isDefault: false), Fixtures.mailboxJSON(id: 2, email: "main@b.c", isDefault: true)]
    ) {
        transport.enqueue("/api/v5/alias/options", json: Fixtures.aliasOptionsJSON(canCreate: canCreate, suffixes: suffixes))
        transport.enqueue("/api/v2/mailboxes", json: Fixtures.mailboxesJSON(mailboxes))
    }

    func loadedModel() async throws -> (NewAliasModel, AppModel) {
        let appModel = try await signedInAppModel()
        let model = NewAliasModel(appModel: appModel)
        await model.load()
        return (model, appModel)
    }

    func createRequestBody() throws -> [String: Any] {
        let request = transport.requests.last { $0.url?.path == "/api/v3/alias/custom/new" }
        let requestBody = try #require(request?.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    }

    func enqueueCreated(email: String = "shop@my.dev") {
        transport.enqueue("/api/v3/alias/custom/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 50, email: email))
    }

    @Test func customSuffixesComeFirstAndTheFirstIsSelected() async throws {
        enqueueChoices(suffixes: [
            Fixtures.suffixJSON("@simplelogin.com", isCustom: false),
            Fixtures.suffixJSON("@my.dev", isCustom: true),
            Fixtures.suffixJSON("@aleeas.com", isCustom: false),
            Fixtures.suffixJSON("@other.dev", isCustom: true),
        ])

        let (model, _) = try await loadedModel()

        #expect(model.suffixes.map(\.suffix) == ["@my.dev", "@other.dev", "@simplelogin.com", "@aleeas.com"])
        #expect(model.suffix?.suffix == "@my.dev")
        #expect(model.errorMessage == nil)
    }

    @Test func creatingIsPossibleOnlyWithAPrefixThatIsNotBlank() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        #expect(model.canSubmit == false)

        model.prefix = "   "
        #expect(model.canSubmit == false)

        model.prefix = "shop"
        #expect(model.canSubmit)
    }

    @Test func theAliasLimitPreventsCreating() async throws {
        enqueueChoices(canCreate: false)
        let (model, _) = try await loadedModel()
        model.prefix = "shop"

        #expect(model.canCreate == false)
        #expect(model.canSubmit == false)
    }

    @Test func withoutAMailboxCreatingIsNotPossible() async throws {
        enqueueChoices(mailboxes: [])
        let (model, _) = try await loadedModel()
        model.prefix = "shop"

        #expect(model.errorMessage == "No mailbox available.")
        #expect(model.canSubmit == false)
    }

    @Test func choicesThatCouldNotLoadShowWhy() async throws {
        let (model, _) = try await loadedModel()
        model.prefix = "shop"

        #expect(model.errorMessage == "Could not reach SimpleLogin. Check your network connection.")
        #expect(model.canSubmit == false)
    }

    @Test func createUsesTheDefaultMailboxAndTheTrimmedPrefix() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "  shop "
        enqueueCreated()

        await model.create()

        let body = try createRequestBody()
        #expect(body["alias_prefix"] as? String == "shop")
        #expect(body["signed_suffix"] as? String == "@my.dev.signed")
        #expect(body["mailbox_ids"] as? [Int] == [2])
    }

    @Test func createUsesTheFirstMailboxWhenNoneIsTheDefault() async throws {
        enqueueChoices(mailboxes: [
            Fixtures.mailboxJSON(id: 4, email: "first@b.c", isDefault: false),
            Fixtures.mailboxJSON(id: 5, email: "second@b.c", isDefault: false),
        ])
        let (model, _) = try await loadedModel()
        model.prefix = "shop"
        enqueueCreated()

        await model.create()

        #expect(try createRequestBody()["mailbox_ids"] as? [Int] == [4])
    }

    @Test func aCreatedAliasIsCopiedAnnouncedAndClosesTheWindow() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "shop"
        enqueueCreated()

        await model.create()

        #expect(model.isComplete)
        #expect(model.errorMessage == nil)
        #expect(copied == ["shop@my.dev"])
        #expect(announced == ["shop@my.dev"])
    }

    @Test func aRejectedAliasShowsTheServerErrorInline() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "ä!"
        transport.enqueue("/api/v3/alias/custom/new", method: "POST", status: 400, json: #"{"error":"Prefix can only contain letters"}"#)

        await model.create()

        #expect(model.errorMessage == "Could not create the alias. Prefix can only contain letters")
        #expect(model.isComplete == false)
        #expect(model.isCreating == false)
        #expect(copied.isEmpty)
    }

    @Test func previewJoinsPrefixAndSuffix() async throws {
        enqueueChoices(suffixes: [Fixtures.suffixJSON("@alexmorgan.example", isCustom: true)])
        let (model, _) = try await loadedModel()
        model.prefix = " concert-tickets "

        #expect(model.previewAddress == "concert-tickets@alexmorgan.example")

        model.prefix = "  "
        #expect(model.previewAddress == nil)
    }

    @Test func previewWaitsForSuffixes() async throws {
        let model = NewAliasModel(appModel: try await signedInAppModel())
        model.prefix = "shop"

        #expect(model.previewAddress == nil)
    }

    @Test func expiryNoteNamesTheDuration() async throws {
        let model = NewAliasModel(appModel: try await signedInAppModel())

        model.expiry = .fiveMinutes
        #expect(model.expiryNote == "off after 5 minutes")
        model.expiry = .oneHour
        #expect(model.expiryNote == "off after 1 hour")
        model.expiry = .twentyFourHours
        #expect(model.expiryNote == "off after 24 hours")
        model.expiry = nil
        #expect(model.expiryNote == nil)
    }

    @Test func suffixesSplitIntoOwnAndShared() async throws {
        enqueueChoices(suffixes: [
            Fixtures.suffixJSON("@simplelogin.com", isCustom: false),
            Fixtures.suffixJSON("@my.dev", isCustom: true),
            Fixtures.suffixJSON("@aleeas.com", isCustom: false),
            Fixtures.suffixJSON("@other.dev", isCustom: true),
        ])

        let (model, _) = try await loadedModel()

        #expect(model.customSuffixes.map(\.suffix) == ["@my.dev", "@other.dev"])
        #expect(model.sharedSuffixes.map(\.suffix) == ["@simplelogin.com", "@aleeas.com"])
    }

    @Test func submitTitleFollowsTheCreateProgress() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "shop"
        #expect(model.submitTitle == "Create")

        transport.holdNext("/api/v3/alias/custom/new", method: "POST", status: 503, json: #"{"error":"SimpleLogin is not responding. Try again in a moment."}"#)
        let create = Task { await model.create() }
        await transport.waitUntilARequestIsHeld()
        #expect(model.submitTitle == "Creating…")

        transport.release()
        await create.value
        #expect(model.submitTitle == "Try Again")
    }

    @Test func failedCreateOffersTryAgain() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "shop"
        transport.enqueue("/api/v3/alias/custom/new", method: "POST", status: 503, json: #"{"error":"SimpleLogin is not responding. Try again in a moment."}"#)

        await model.create()

        #expect(model.errorMessage == "Could not create the alias. SimpleLogin is not responding. Try again in a moment.")
        #expect(model.submitTitle == "Try Again")
        #expect(model.canSubmit)
    }

    @Test func anAliasThatExistsDespiteTheErrorKeepsCreateAndTheUnprefixedMessage() async throws {
        enqueueChoices()
        let appModel = try await signedInAppModel(timerStore: UnavailableTimerStore(reason: "test"))
        let model = NewAliasModel(appModel: appModel)
        await model.load()
        model.prefix = "shop"
        model.expiry = .fiveMinutes
        enqueueCreated()

        await model.create()

        #expect(model.errorMessage == "shop@my.dev was created, but its timer could not start and it is still enabled.")
        #expect(model.submitTitle == "Create")
        #expect(model.isComplete == false)
    }

    @Test func anAliasDisabledAgainBecauseItsTimerCouldNotStartKeepsCreateAndTheUnprefixedMessage() async throws {
        enqueueChoices()
        let appModel = try await signedInAppModel(timerStore: UnavailableTimerStore(reason: "test"))
        let model = NewAliasModel(appModel: appModel)
        await model.load()
        model.prefix = "shop"
        model.expiry = .fiveMinutes
        enqueueCreated()
        transport.enqueue("/api/aliases/50", json: Fixtures.newAliasJSON(id: 50, email: "shop@my.dev"))
        transport.enqueue("/api/aliases/50/toggle", method: "POST", json: Fixtures.toggleJSON(enabled: false))

        await model.create()

        #expect(model.errorMessage == "shop@my.dev was created, but its timer could not start, so it was disabled again.")
        #expect(model.submitTitle == "Create")
        #expect(model.isComplete == false)
    }

    @Test func tryAgainResubmitsAndClearsTheErrorOnSuccess() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "shop"
        transport.enqueue("/api/v3/alias/custom/new", method: "POST", status: 503, json: #"{"error":"SimpleLogin is not responding. Try again in a moment."}"#)
        await model.create()
        enqueueCreated()

        await model.create()

        #expect(model.isComplete)
        #expect(model.errorMessage == nil)
        #expect(copied == ["shop@my.dev"])
    }

    @Test func theChosenExpiryStartsATimer() async throws {
        enqueueChoices()
        let (model, appModel) = try await loadedModel()
        model.prefix = "shop"
        model.expiry = .fiveMinutes
        enqueueCreated()

        await model.create()

        #expect(appModel.engine.record(for: 50)?.expiresAt == clock.now.addingTimeInterval(300))
    }

    @Test func aCreateFinishingAfterResetIsIgnored() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "shop"
        transport.holdNext("/api/v3/alias/custom/new", method: "POST", status: 201, json: Fixtures.newAliasJSON(id: 50, email: "shop@my.dev"))
        let create = Task { await model.create() }
        await transport.waitUntilARequestIsHeld()

        model.reset()
        transport.release()
        await create.value

        #expect(model.isComplete == false)
        #expect(model.errorMessage == nil)
    }

    @Test func resetStartsOverWithNeverAsTheExpiry() async throws {
        enqueueChoices()
        let (model, _) = try await loadedModel()
        model.prefix = "shop"
        model.expiry = .oneHour
        enqueueCreated()
        await model.create()

        model.reset()

        #expect(model.prefix.isEmpty)
        #expect(model.expiry == nil)
        #expect(model.isComplete == false)
        #expect(model.errorMessage == nil)
        #expect(model.suffixes.isEmpty)
        #expect(model.submitTitle == "Create")
    }
}
