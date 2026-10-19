import Foundation
import Security

public protocol APIKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

public enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    private let service: String
    private let account: String

    public init(service: String = "de.dieserjonas.ajour", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    public func load() throws -> String? {
        var query = identityQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(
            identityQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try add(data)
        default:
            throw KeychainError.status(updateStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(identityQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private var identityQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func add(_ data: Data) throws {
        var attributes = identityQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }
}

public enum APIKeyFormat {
    public static func looksLikeAPIKey(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.utf8.count == 60 && trimmed.utf8.allSatisfy { (97...122).contains($0) }
    }
}
