import Foundation
import Testing
import SimpleLoginKit
@testable import Ajour

struct MenuTitleTests {
    @Test func aDisabledAliasShowsAnEmptyCircle() {
        let item = MenuAliasItem(id: 1, email: "shop@example.com", state: .disabled)

        #expect(item.menuTitle == "○ shop@example.com")
    }

    @Test func aPermanentlyEnabledAliasShowsAFilledCircle() {
        let item = MenuAliasItem(id: 1, email: "shop@example.com", state: .enabled)

        #expect(item.menuTitle == "● shop@example.com")
    }

    @Test func aTimedAliasShowsTheRemainingTime() {
        let item = MenuAliasItem(id: 1, email: "shop@example.com", state: .timed(remaining: 192, endsAt: Date(timeIntervalSince1970: 192), length: 300))

        #expect(item.menuTitle == "● shop@example.com · 3:12 left")
    }

    @Test func aShortErrorIsShownInFull() {
        let message = String(repeating: "a", count: 80)

        #expect(MenuEntry.errorTitle(for: message) == message)
    }

    @Test func aLongErrorIsShortenedToEightyCharacters() {
        let message = String(repeating: "a", count: 81)

        #expect(MenuEntry.errorTitle(for: message) == String(repeating: "a", count: 79) + "…")
    }
}
