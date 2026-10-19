#if DEBUG
import Foundation
import SimpleLoginKit

/// Run the built app with `-verifyKeychainAccess` to confirm the sandboxed app can save, read, and delete
/// a Keychain item. It uses its own item with a random value, so the real API key is never touched.
enum KeychainAccessCheck {
    static let launchArgument = "-verifyKeychainAccess"

    static var isRequested: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    static func run() -> Never {
        let store = KeychainAPIKeyStore(service: "de.doebertin.simplelogin-macos.keychain-check", account: "check")
        let value = UUID().uuidString
        do {
            try store.save(value)
            let loaded = try store.load()
            try store.delete()
            let afterDelete = try store.load()
            let passed = loaded == value && afterDelete == nil
            print("Keychain access check \(passed ? "passed" : "failed"): save, load, delete")
            exit(passed ? 0 : 1)
        } catch {
            print("Keychain access check failed: \(error)")
            exit(1)
        }
    }
}
#endif
