import Foundation

public enum AliasSwitchError: Error, Equatable {
    case unexpectedState(aliasID: Int)
}

public struct AliasSwitch: Sendable {
    private let api: any AliasAPI
    private let retry: RetryPolicy

    public init(api: any AliasAPI, retry: RetryPolicy = .standard) {
        self.api = api
        self.retry = retry
    }

    public func ensureEnabled(aliasID: Int) async throws -> Alias {
        try await ensure(enabled: true, aliasID: aliasID)
    }

    public func ensureDisabled(aliasID: Int) async throws -> Alias {
        try await ensure(enabled: false, aliasID: aliasID)
    }

    /// A toggle that fails in transit may still have been applied, so a retry reads the alias again
    /// instead of toggling blindly. Toggling twice would put the alias back in its old state.
    private func ensure(enabled desired: Bool, aliasID: Int) async throws -> Alias {
        var togglesSent = 0
        while true {
            let current = try await api.alias(id: aliasID)
            guard current.enabled != desired else { return current }
            do {
                togglesSent += 1
                let enabledAfterToggle = try await api.toggle(aliasID: aliasID)
                guard enabledAfterToggle == desired else {
                    throw AliasSwitchError.unexpectedState(aliasID: aliasID)
                }
                return current.settingEnabled(enabledAfterToggle)
            } catch let error as APIError where error.isTransient && togglesSent < retry.attempts {
                try await Task.sleep(for: retry.delay)
            }
        }
    }
}

extension Alias {
    public func settingEnabled(_ enabled: Bool) -> Alias {
        Alias(
            id: id,
            email: email,
            name: name,
            enabled: enabled,
            note: note,
            pinned: pinned,
            nbBlock: nbBlock,
            nbForward: nbForward,
            latestActivity: latestActivity,
            mailboxes: mailboxes
        )
    }
}
