import Foundation
import Testing
@testable import SimpleLoginKit

@Suite struct APIKeyStoreTests {
    @Test func keychainRoundTrip() throws {
        let store = KeychainAPIKeyStore(service: "test-" + UUID().uuidString)
        defer { try? store.delete() }

        #expect(try store.load() == nil)

        try store.save("first")
        #expect(try store.load() == "first")

        try store.save("second")
        #expect(try store.load() == "second")

        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test func deletingMissingKeyDoesNotThrow() throws {
        let store = KeychainAPIKeyStore(service: "test-" + UUID().uuidString)
        try store.delete()
    }

    @Test func heuristicAcceptsSixtyLowercaseLetters() {
        #expect(APIKeyFormat.looksLikeAPIKey(String(repeating: "a", count: 60)))
    }

    @Test func heuristicTrimsWhitespace() {
        let key = String(repeating: "k", count: 60)
        #expect(APIKeyFormat.looksLikeAPIKey("  \(key)\n"))
    }

    @Test func heuristicRejectsShortUppercaseOrSpaces() {
        #expect(!APIKeyFormat.looksLikeAPIKey(String(repeating: "a", count: 59)))
        #expect(!APIKeyFormat.looksLikeAPIKey(String(repeating: "a", count: 61)))
        #expect(!APIKeyFormat.looksLikeAPIKey(String(repeating: "A", count: 60)))
        #expect(!APIKeyFormat.looksLikeAPIKey(String(repeating: "a", count: 30) + " " + String(repeating: "a", count: 30)))
        #expect(!APIKeyFormat.looksLikeAPIKey(String(repeating: "a", count: 59) + "1"))
        #expect(!APIKeyFormat.looksLikeAPIKey(""))
    }
}
