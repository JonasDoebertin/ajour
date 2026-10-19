import Foundation
import Testing
import UserNotifications
import SimpleLoginKit
@testable import SimpleLoginMac

struct NotificationContentFactoryTests {
    let arrival = MailArrival(
        aliasID: 7,
        aliasEmail: "shop@example.com",
        sender: "login@shop.com",
        timestamp: Date(timeIntervalSince1970: 1_800_000_000)
    )

    @Test func mailArrivalNamesTheAliasAndTheSender() {
        let content = NotificationContentFactory.content(for: arrival)

        #expect(content.title == "Mail received")
        #expect(content.body == "shop@example.com from login@shop.com")
    }

    @Test func mailArrivalOffersDisablingTheAlias() {
        let content = NotificationContentFactory.content(for: arrival)

        #expect(content.categoryIdentifier == "MAIL_RECEIVED")
        #expect(content.aliasID == 7)
    }

    @Test func theSameMailArrivalKeepsItsIdentifierSoARepeatReplacesIt() {
        let first = NotificationContentFactory.content(for: arrival)
        let repeated = NotificationContentFactory.content(for: arrival)

        #expect(first.identifier == "mail-7-1800000000")
        #expect(repeated.identifier == first.identifier)
    }

    @Test func laterMailToTheSameAliasGetsItsOwnIdentifier() {
        let later = MailArrival(aliasID: 7, aliasEmail: "shop@example.com", sender: "news@shop.com", timestamp: arrival.timestamp.addingTimeInterval(60))

        let identifiers = [arrival, later].map { NotificationContentFactory.content(for: $0).identifier }

        #expect(identifiers[0] != identifiers[1])
    }

    @Test func persistentDisableFailureSaysTheAppKeepsTrying() throws {
        let content = try #require(NotificationContentFactory.content(for: .disableKeepsFailing(aliasID: 7, email: "shop@example.com")))

        #expect(content.title == "Could not disable alias")
        #expect(content.body == "shop@example.com is still enabled. Will keep trying.")
        #expect(content.categoryIdentifier == "")
        #expect(content.aliasID == 7)
    }

    @Test func forbiddenDisableSaysTheCurrentKeyCannotDisableTheAlias() throws {
        let content = try #require(NotificationContentFactory.content(for: .disableForbidden(aliasID: 7, email: "shop@example.com")))

        #expect(content.title == "Could not disable alias")
        #expect(content.body == "shop@example.com can't be disabled with the current API key.")
        #expect(content.identifier == "disable-forbidden-7")
        #expect(content.categoryIdentifier == "")
        #expect(content.aliasID == 7)
    }

    @Test func invalidAPIKeyAsksToReEnterIt() throws {
        let content = try #require(NotificationContentFactory.content(for: .unauthorized))

        #expect(content.title == "API key invalid")
        #expect(content.body == "Re-enter your SimpleLogin API key in Settings.")
        #expect(content.categoryIdentifier == "")
    }

    @Test func aRegularDisableShowsNoNotification() {
        #expect(NotificationContentFactory.content(for: .disabled(aliasID: 7, email: "shop@example.com")) == nil)
    }

    @Test func copiedAliasShowsTheAddress() {
        let content = NotificationContentFactory.copied(email: "shop@example.com")

        #expect(content.title == "Alias copied")
        #expect(content.body == "shop@example.com")
        #expect(content.categoryIdentifier == "")
    }
}

struct NotificationResponseRouterTests {
    @Test func theDisableNowButtonDisablesTheAlias() {
        let aliasID = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: "MAIL_RECEIVED",
            actionIdentifier: "DISABLE_NOW",
            userInfo: ["aliasID": 7]
        )

        #expect(aliasID == 7)
    }

    @Test func clickingTheMailNotificationDisablesTheAlias() {
        let aliasID = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: "MAIL_RECEIVED",
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ["aliasID": 7]
        )

        #expect(aliasID == 7)
    }

    @Test func dismissingTheMailNotificationKeepsTheAlias() {
        let aliasID = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: "MAIL_RECEIVED",
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: ["aliasID": 7]
        )

        #expect(aliasID == nil)
    }

    @Test func clickingAnotherNotificationDisablesNothing() {
        let aliasID = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: "",
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ["aliasID": 7]
        )

        #expect(aliasID == nil)
    }

    @Test func aMailNotificationWithoutAnAliasDisablesNothing() {
        let missing = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: "MAIL_RECEIVED",
            actionIdentifier: "DISABLE_NOW",
            userInfo: [:]
        )
        let malformed = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: "MAIL_RECEIVED",
            actionIdentifier: "DISABLE_NOW",
            userInfo: ["aliasID": "7"]
        )

        #expect(missing == nil)
        #expect(malformed == nil)
    }
}
