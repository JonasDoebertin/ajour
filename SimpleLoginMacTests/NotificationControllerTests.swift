import Foundation
import Testing
import UserNotifications
import SimpleLoginKit
@testable import SimpleLoginMac

@MainActor
struct NotificationControllerTests {
    let center = FakeNotificationCenter()
    let arrival = MailArrival(
        aliasID: 7,
        aliasEmail: "shop@example.com",
        sender: "login@shop.com",
        timestamp: Date(timeIntervalSince1970: 1_800_000_000)
    )

    func makeController(onDisableRequested: @escaping (Int) -> Void = { _ in }) -> NotificationController {
        NotificationController(center: center, onDisableRequested: onDisableRequested)
    }

    @Test func activatingBecomesTheCenterDelegate() {
        let controller = makeController()

        controller.activate()

        #expect(center.delegate === controller)
    }

    @Test func activatingRegistersTheDisableNowAction() throws {
        let controller = makeController()

        controller.activate()

        let category = try #require(center.categories.first { $0.identifier == "MAIL_RECEIVED" })
        #expect(category.actions.map(\.identifier) == ["DISABLE_NOW"])
        #expect(category.actions.map(\.title) == ["Disable Now"])
    }

    @Test func requestingAuthorizationAsksForAlertsAndSounds() async {
        let controller = makeController()

        await controller.requestAuthorization()

        #expect(center.authorizationRequests == [[.alert, .sound]])
    }

    @Test func postingAMailArrivalDeliversADisableableNotification() throws {
        let controller = makeController()

        controller.post(arrival)

        let request = try #require(center.addedRequests.only)
        #expect(request.identifier == "mail-7-1800000000")
        #expect(request.content.title == "Mail received")
        #expect(request.content.body == "shop@example.com from login@shop.com")
        #expect(request.content.categoryIdentifier == "MAIL_RECEIVED")
        #expect(request.content.userInfo["aliasID"] as? Int == 7)
        #expect(request.content.sound != nil)
        #expect(request.trigger == nil)
    }

    @Test func postingAPersistentDisableFailureDeliversANotification() throws {
        let controller = makeController()

        controller.post(.disableKeepsFailing(aliasID: 7, email: "shop@example.com"))

        let request = try #require(center.addedRequests.only)
        #expect(request.content.title == "Could not disable alias")
        #expect(request.identifier == "disable-failing-7")
    }

    @Test func postingAnInvalidAPIKeyDeliversANotification() throws {
        let controller = makeController()

        controller.post(.unauthorized)

        let request = try #require(center.addedRequests.only)
        #expect(request.content.title == "API key invalid")
    }

    @Test func postingARegularDisableDeliversNothing() {
        let controller = makeController()

        controller.post(.disabled(aliasID: 7, email: "shop@example.com"))

        #expect(center.addedRequests.isEmpty)
    }

    @Test func postingACopiedAliasDeliversAQuietConfirmation() throws {
        let controller = makeController()

        controller.postCopied(email: "shop@example.com")

        let request = try #require(center.addedRequests.only)
        #expect(request.content.title == "Alias copied")
        #expect(request.content.body == "shop@example.com")
        #expect(request.content.sound == nil)
    }

    @Test func aDisabledAliasLosesItsMailNotifications() {
        let controller = makeController()
        let later = MailArrival(aliasID: 7, aliasEmail: "shop@example.com", sender: "news@shop.com", timestamp: arrival.timestamp.addingTimeInterval(60))
        let otherAlias = MailArrival(aliasID: 70, aliasEmail: "news@example.com", sender: "news@shop.com", timestamp: arrival.timestamp)
        [arrival, later, otherAlias].forEach(controller.post)

        controller.removeNotifications(aliasID: 7)

        #expect(Set(center.removedIdentifiers) == ["mail-7-1800000000", "mail-7-1800000060"])
    }

    @Test func anExpiredAliasLosesItsMailNotifications() {
        let controller = makeController()
        controller.post(arrival)

        controller.post(.disabled(aliasID: 7, email: "shop@example.com"))

        #expect(center.removedIdentifiers == ["mail-7-1800000000"])
    }

    @Test func aDisabledAliasLosesItsStaleDisableFailure() {
        let controller = makeController()
        controller.post(.disableKeepsFailing(aliasID: 7, email: "shop@example.com"))

        controller.post(.disabled(aliasID: 7, email: "shop@example.com"))

        #expect(center.removedIdentifiers == ["disable-failing-7"])
    }

    @Test func removedNotificationsAreNotRemovedAgain() {
        let controller = makeController()
        controller.post(arrival)
        controller.removeNotifications(aliasID: 7)

        controller.removeNotifications(aliasID: 7)

        #expect(center.removedIdentifiers == ["mail-7-1800000000"])
    }

    @Test func aResponseToDisableTheAliasIsForwarded() async {
        var requestedAliasIDs: [Int] = []
        let controller = makeController { requestedAliasIDs.append($0) }

        await controller.handleResponse(categoryIdentifier: "MAIL_RECEIVED", actionIdentifier: "DISABLE_NOW", userInfo: ["aliasID": 7])
        await controller.handleResponse(categoryIdentifier: "", actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: [:])

        #expect(requestedAliasIDs == [7])
    }

    @Test func notificationsShowWhileTheAppIsActive() {
        #expect(NotificationController.presentationOptions == [.banner, .sound])
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
