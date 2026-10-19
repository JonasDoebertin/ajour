import Testing
import SimpleLoginKit
@testable import SimpleLoginMac

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
        let item = MenuAliasItem(id: 1, email: "shop@example.com", state: .timed(remaining: 192))

        #expect(item.menuTitle == "● shop@example.com · 3:12 left")
    }

    @Test func aShortErrorIsShownInFull() {
        let message = String(repeating: "a", count: 80)

        #expect(MenuContent.errorTitle(for: message) == message)
    }

    @Test func aLongErrorIsShortenedToEightyCharacters() {
        let message = String(repeating: "a", count: 81)

        #expect(MenuContent.errorTitle(for: message) == String(repeating: "a", count: 79) + "…")
    }
}
