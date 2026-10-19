import SimpleLoginKit
import UserNotifications

/// What a notification shows, independent of UserNotifications, so its copy and identity can be checked directly.
struct NotificationContent: Equatable {
    let identifier: String
    let title: String
    let body: String
    var categoryIdentifier = ""
    var aliasID: Int?
    var playsSound = true
}

enum NotificationIdentifier {
    static let mailReceivedCategory = "MAIL_RECEIVED"
    static let disableNowAction = "DISABLE_NOW"
    static let aliasIDKey = "aliasID"
}

enum NotificationContentFactory {
    /// The identifier is derived from the activity, so the same mail seen twice replaces its notification.
    static func content(for arrival: MailArrival) -> NotificationContent {
        NotificationContent(
            identifier: "mail-\(arrival.aliasID)-\(Int(arrival.timestamp.timeIntervalSince1970))",
            title: "Mail received",
            body: "\(arrival.aliasEmail) from \(arrival.sender)",
            categoryIdentifier: NotificationIdentifier.mailReceivedCategory,
            aliasID: arrival.aliasID
        )
    }

    static func content(for event: TimerEvent) -> NotificationContent? {
        switch event {
        case .disabled:
            nil
        case .disableKeepsFailing(let aliasID, let email):
            NotificationContent(
                identifier: "disable-failing-\(aliasID)",
                title: "Could not disable alias",
                body: "\(email) is still enabled. Will keep trying.",
                aliasID: aliasID
            )
        case .disableForbidden(let aliasID, let email):
            NotificationContent(
                identifier: "disable-forbidden-\(aliasID)",
                title: "Could not disable alias",
                body: "\(email) can't be disabled with the current API key.",
                aliasID: aliasID
            )
        case .unauthorized:
            NotificationContent(
                identifier: "api-key-invalid",
                title: "API key invalid",
                body: "Re-enter your SimpleLogin API key in Settings."
            )
        }
    }

    static func copied(email: String) -> NotificationContent {
        NotificationContent(identifier: "alias-copied", title: "Alias copied", body: email, playsSound: false)
    }
}

enum NotificationResponseRouter {
    /// Both the "Disable Now" button and a click on a mail notification disable its alias.
    static func aliasToDisable(categoryIdentifier: String, actionIdentifier: String, userInfo: [AnyHashable: Any]) -> Int? {
        guard categoryIdentifier == NotificationIdentifier.mailReceivedCategory,
              [NotificationIdentifier.disableNowAction, UNNotificationDefaultActionIdentifier].contains(actionIdentifier)
        else { return nil }
        return userInfo[NotificationIdentifier.aliasIDKey] as? Int
    }
}

/// The part of `UNUserNotificationCenter` the app uses, so tests can stand in for the system.
@MainActor protocol UserNotificationCenter: AnyObject {
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest)
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

/// Looks up the system center only when used, so creating the controller in the test host touches nothing.
@MainActor final class SystemNotificationCenter: UserNotificationCenter {
    private var center: UNUserNotificationCenter { .current() }

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        center.delegate = delegate
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) {
        center.add(request, withCompletionHandler: nil)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let presentationOptions: UNNotificationPresentationOptions = [.banner, .sound]

    private let center: any UserNotificationCenter
    private let onDisableRequested: (Int) -> Void
    /// Notifications about an alias, so they can be withdrawn once it is disabled.
    private var aliasNotificationIdentifiers: [Int: Set<String>] = [:]

    init(center: any UserNotificationCenter = SystemNotificationCenter(), onDisableRequested: @escaping (Int) -> Void) {
        self.center = center
        self.onDisableRequested = onDisableRequested
    }

    /// Must run before the app finishes launching, so a click that launches the app still reaches the delegate.
    func activate() {
        center.setDelegate(self)
        let disableNow = UNNotificationAction(identifier: NotificationIdentifier.disableNowAction, title: "Disable Now")
        let mailReceived = UNNotificationCategory(
            identifier: NotificationIdentifier.mailReceivedCategory,
            actions: [disableNow],
            intentIdentifiers: []
        )
        center.setNotificationCategories([mailReceived])
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ arrival: MailArrival) {
        deliver(NotificationContentFactory.content(for: arrival))
    }

    func post(_ event: TimerEvent) {
        if case .disabled(let aliasID, _) = event {
            removeNotifications(aliasID: aliasID)
        }
        guard let content = NotificationContentFactory.content(for: event) else { return }
        deliver(content)
    }

    func postCopied(email: String) {
        deliver(NotificationContentFactory.copied(email: email))
    }

    /// Offering "Disable Now" or saying "still enabled" for an alias that is already disabled would only confuse.
    func removeNotifications(aliasID: Int) {
        guard let identifiers = aliasNotificationIdentifiers.removeValue(forKey: aliasID) else { return }
        center.removeDeliveredNotifications(withIdentifiers: Array(identifiers))
    }

    nonisolated func handleResponse(categoryIdentifier: String, actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        guard let aliasID = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: categoryIdentifier,
            actionIdentifier: actionIdentifier,
            userInfo: userInfo
        ) else { return }
        await requestDisable(aliasID: aliasID)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        await handleResponse(
            categoryIdentifier: content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: content.userInfo
        )
    }

    /// A menu bar app counts as active while its menu is open, and banners should show then too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.presentationOptions
    }

    private func requestDisable(aliasID: Int) {
        onDisableRequested(aliasID)
    }

    private func deliver(_ content: NotificationContent) {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.categoryIdentifier = content.categoryIdentifier
        if let aliasID = content.aliasID {
            notification.userInfo = [NotificationIdentifier.aliasIDKey: aliasID]
            aliasNotificationIdentifiers[aliasID, default: []].insert(content.identifier)
        }
        if content.playsSound {
            notification.sound = .default
        }
        center.add(UNNotificationRequest(identifier: content.identifier, content: notification, trigger: nil))
    }
}
