import Foundation

public struct Alias: Decodable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let email: String
    public let name: String?
    public let enabled: Bool
    public let note: String?
    public let pinned: Bool
    public let nbBlock: Int
    public let nbForward: Int
    public let latestActivity: AliasActivity?
    public let mailboxes: [MailboxRef]

    public init(
        id: Int,
        email: String,
        name: String?,
        enabled: Bool,
        note: String?,
        pinned: Bool,
        nbBlock: Int,
        nbForward: Int,
        latestActivity: AliasActivity?,
        mailboxes: [MailboxRef]
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.enabled = enabled
        self.note = note
        self.pinned = pinned
        self.nbBlock = nbBlock
        self.nbForward = nbForward
        self.latestActivity = latestActivity
        self.mailboxes = mailboxes
    }
}

public struct AliasActivity: Decodable, Equatable, Sendable {
    public enum Action: String, Decodable, Sendable {
        case forward, reply, block, bounced, other

        public init(from decoder: any Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = Action(rawValue: rawValue) ?? .other
        }
    }

    public let action: Action
    public let timestamp: Date
    public let contact: AliasContact

    public init(action: Action, timestamp: Date, contact: AliasContact) {
        self.action = action
        self.timestamp = timestamp
        self.contact = contact
    }
}

public struct AliasContact: Decodable, Equatable, Sendable {
    public let email: String
    public let name: String?

    public init(email: String, name: String?) {
        self.email = email
        self.name = name
    }
}

public struct MailboxRef: Decodable, Equatable, Sendable {
    public let id: Int
    public let email: String

    public init(id: Int, email: String) {
        self.id = id
        self.email = email
    }
}

public struct Mailbox: Decodable, Equatable, Sendable {
    public let id: Int
    public let email: String
    public let isDefault: Bool

    public init(id: Int, email: String, isDefault: Bool) {
        self.id = id
        self.email = email
        self.isDefault = isDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id, email
        case isDefault = "default"
    }
}

public struct AliasOptions: Decodable, Equatable, Sendable {
    public let canCreate: Bool
    public let suffixes: [AliasSuffix]

    public init(canCreate: Bool, suffixes: [AliasSuffix]) {
        self.canCreate = canCreate
        self.suffixes = suffixes
    }
}

public struct AliasSuffix: Decodable, Equatable, Sendable, Hashable {
    public let suffix: String
    public let signedSuffix: String
    public let isCustom: Bool
    public let isPremium: Bool

    public init(suffix: String, signedSuffix: String, isCustom: Bool, isPremium: Bool) {
        self.suffix = suffix
        self.signedSuffix = signedSuffix
        self.isCustom = isCustom
        self.isPremium = isPremium
    }
}

public enum AliasFilter: String, Sendable {
    case pinned, enabled, disabled
}
