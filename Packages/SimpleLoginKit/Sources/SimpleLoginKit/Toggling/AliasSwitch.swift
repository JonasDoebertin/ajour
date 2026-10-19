import Foundation

public enum AliasSwitchError: Error, Equatable {
    case unexpectedState(aliasID: Int)
}

public struct AliasSwitch: Sendable {
    private let api: any AliasAPI

    public init(api: any AliasAPI) {
        self.api = api
    }

    public func ensureEnabled(aliasID: Int) async throws -> Alias {
        try await ensure(enabled: true, aliasID: aliasID)
    }

    public func ensureDisabled(aliasID: Int) async throws -> Alias {
        try await ensure(enabled: false, aliasID: aliasID)
    }

    private func ensure(enabled desired: Bool, aliasID: Int) async throws -> Alias {
        let current = try await api.alias(id: aliasID)
        guard current.enabled != desired else { return current }
        let enabledAfterToggle = try await api.toggle(aliasID: aliasID)
        guard enabledAfterToggle == desired else {
            throw AliasSwitchError.unexpectedState(aliasID: aliasID)
        }
        return current.settingEnabled(enabledAfterToggle)
    }
}

extension Alias {
    fileprivate func settingEnabled(_ enabled: Bool) -> Alias {
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
