import Foundation
@testable import SimpleLoginKit

final class FakeAliasAPI: AliasAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAliases: [Int: Alias]
    private var storedErrors: [Error] = []
    private var storedToggleErrors: [Error] = []
    private var storedToggleErrorsAfterApplying: [Error] = []
    private var storedToggleCalls: [Int] = []
    private var storedAliasCalls: [Int] = []

    init(aliases: [Alias] = []) {
        storedAliases = Dictionary(uniqueKeysWithValues: aliases.map { ($0.id, $0) })
    }

    var aliases: [Int: Alias] {
        get { lock.withLock { storedAliases } }
        set { lock.withLock { storedAliases = newValue } }
    }

    var errors: [Error] {
        get { lock.withLock { storedErrors } }
        set { lock.withLock { storedErrors = newValue } }
    }

    /// Thrown by `toggle` before it flips the alias, like a request that never arrived.
    var toggleErrors: [Error] {
        get { lock.withLock { storedToggleErrors } }
        set { lock.withLock { storedToggleErrors = newValue } }
    }

    /// Thrown by `toggle` after it flipped the alias, like a response that never made it back.
    var toggleErrorsAfterApplying: [Error] {
        get { lock.withLock { storedToggleErrorsAfterApplying } }
        set { lock.withLock { storedToggleErrorsAfterApplying = newValue } }
    }

    var toggleCalls: [Int] {
        lock.withLock { storedToggleCalls }
    }

    var aliasCalls: [Int] {
        lock.withLock { storedAliasCalls }
    }

    func alias(id: Int) async throws -> Alias {
        try lock.withLock {
            storedAliasCalls.append(id)
            try popError()
            guard let alias = storedAliases[id] else {
                throw APIError.server(status: 404, message: "Alias not found")
            }
            return alias
        }
    }

    func toggle(aliasID: Int) async throws -> Bool {
        try lock.withLock {
            try popError()
            if !storedToggleErrors.isEmpty {
                throw storedToggleErrors.removeFirst()
            }
            storedToggleCalls.append(aliasID)
            guard let alias = storedAliases[aliasID] else {
                throw APIError.server(status: 404, message: "Alias not found")
            }
            let flipped = Alias(
                id: alias.id,
                email: alias.email,
                name: alias.name,
                enabled: !alias.enabled,
                note: alias.note,
                pinned: alias.pinned,
                nbBlock: alias.nbBlock,
                nbForward: alias.nbForward,
                latestActivity: alias.latestActivity,
                mailboxes: alias.mailboxes
            )
            storedAliases[aliasID] = flipped
            if !storedToggleErrorsAfterApplying.isEmpty {
                throw storedToggleErrorsAfterApplying.removeFirst()
            }
            return flipped.enabled
        }
    }

    private func popError() throws {
        if !storedErrors.isEmpty {
            throw storedErrors.removeFirst()
        }
    }
}
