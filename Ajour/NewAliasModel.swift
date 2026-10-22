import Foundation
import Observation
import SimpleLoginKit

/// Creates a custom alias from a prefix and one of the account's suffixes, delivered to the default mailbox.
@MainActor @Observable final class NewAliasModel {
    var prefix = ""
    var suffix: AliasSuffix?
    /// `nil` keeps the alias enabled until the user disables it.
    var expiry: AliasDuration?
    /// Custom domains first, because those are the reason to pick a suffix by hand.
    private(set) var suffixes: [AliasSuffix] = []
    /// False once the account's alias limit is reached.
    private(set) var canCreate = true
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var isCreating = false
    private(set) var isComplete = false
    private var createFailed = false
    private var mailbox: Mailbox?
    /// Changes on reset, so a create that finishes after the window closed doesn't affect the next one.
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var canSubmit: Bool {
        canCreate && suffix != nil && mailbox != nil && !trimmedPrefix.isEmpty && !isCreating
    }

    var customSuffixes: [AliasSuffix] {
        suffixes.filter(\.isCustom)
    }

    var sharedSuffixes: [AliasSuffix] {
        suffixes.filter { !$0.isCustom }
    }

    /// The address the alias will get, once there is a prefix and the suffixes have loaded.
    var previewAddress: String? {
        guard let suffix, !trimmedPrefix.isEmpty else { return nil }
        return trimmedPrefix + suffix.suffix
    }

    var expiryNote: String? {
        expiry.map { "off after \($0.title.lowercased())" }
    }

    var submitTitle: String {
        if isCreating { "Creating…" } else if createFailed { "Try Again" } else { "Create" }
    }

    func load() async {
        guard let api = appModel.api else {
            errorMessage = AppModel.userMessage(for: TimerEngineError.notSignedIn)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let options = api.aliasOptions()
            async let mailboxes = api.mailboxes()
            let (loadedOptions, loadedMailboxes) = try await (options, mailboxes)
            canCreate = loadedOptions.canCreate
            suffixes = loadedOptions.suffixes.filter(\.isCustom) + loadedOptions.suffixes.filter { !$0.isCustom }
            suffix = suffixes.first
            mailbox = loadedMailboxes.first(where: \.isDefault) ?? loadedMailboxes.first
            errorMessage = mailbox == nil ? "No mailbox available." : nil
        } catch {
            errorMessage = AppModel.userMessage(for: error)
        }
    }

    func create() async {
        guard canSubmit, let suffix, let mailbox else { return }
        let generation = self.generation
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            _ = try await appModel.createCustomAlias(prefix: trimmedPrefix, suffix: suffix, mailboxID: mailbox.id, expiringAfter: expiry)
            guard generation == self.generation else { return }
            createFailed = false
            isComplete = true
        } catch {
            guard generation == self.generation else { return }
            createFailed = true
            errorMessage = "Could not create the alias. " + AppModel.userMessage(for: error)
        }
    }

    func reset() {
        generation += 1
        prefix = ""
        suffix = nil
        expiry = nil
        suffixes = []
        canCreate = true
        mailbox = nil
        errorMessage = nil
        createFailed = false
        isComplete = false
    }

    private var trimmedPrefix: String {
        prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
