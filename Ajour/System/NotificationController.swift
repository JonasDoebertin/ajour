import SimpleLoginKit
import UserNotifications

/// What a notification shows, independent of UserNotifications, so its copy and identity can be checked directly.
struct NotificationContent: Equatable {
    let identifier: String
    let title: String
    let body: String
    var subtitle = ""
    var categoryIdentifier = ""
    var aliasID: Int?
    var playsSound = true
}

enum NotificationIdentifier {
    static let mailReceivedCategory = "MAIL_RECEIVED"
    static let disableNowAction = "DISABLE_NOW"
    static let disableFailedCategory = "DISABLE_FAILED"
    static let tryAgainAction = "TRY_AGAIN"
    static let aliasIDKey = "aliasID"
}

enum NotificationContentFactory {
    /// The identifier is derived from the activity, so the same mail seen twice replaces its notification.
    static func content(
        for arrival: MailArrival,
        turnsOffAt: Date?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> NotificationContent {
        NotificationContent(
            identifier: "mail-\(arrival.aliasID)-\(Int(arrival.timestamp.timeIntervalSince1970))",
            title: "Mail received",
            body: "\(arrival.aliasEmail) from \(arrival.sender)",
            subtitle: turnsOffAt.map { "Alias turns off at \(AliasStatus.shortTime($0, locale: locale, timeZone: timeZone))" } ?? "",
            categoryIdentifier: NotificationIdentifier.mailReceivedCategory,
            aliasID: arrival.aliasID
        )
    }

    static func content(for event: TimerEvent) -> NotificationContent? {
        switch event {
        case .disabled:
            nil
        case .disableKeepsFailing(let aliasID, let email, let problem):
            NotificationContent(
                identifier: "disable-failing-\(aliasID)",
                title: "Could not disable alias",
                body: "\(email) is still enabled. \(reason(for: problem)) Ajour keeps trying.",
                categoryIdentifier: NotificationIdentifier.disableFailedCategory,
                aliasID: aliasID
            )
        case .disableForbidden(let aliasID, let email):
            NotificationContent(
                identifier: "disable-forbidden-\(aliasID)",
                title: "Could not disable alias",
                body: "The current API key can't change \(email), so it stays enabled. Keep it enabled or use a different key from the menu.",
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

    private static func reason(for problem: DisableProblem) -> String {
        switch problem {
        case .unreachable:
            "SimpleLogin can't be reached."
        case .notResponding(let status):
            "SimpleLogin isn't responding (error \(status))."
        case .keyRejected, .refused, .other:
            "SimpleLogin reported an error."
        }
    }

    static func copied(email: String) -> NotificationContent {
        NotificationContent(identifier: "alias-copied", title: "Alias copied", body: "\(email) is on the clipboard.", playsSound: false)
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

    /// Both the "Try Again" button and a click on a failed-disable notification retry its alias.
    static func aliasToRetry(categoryIdentifier: String, actionIdentifier: String, userInfo: [AnyHashable: Any]) -> Int? {
        guard categoryIdentifier == NotificationIdentifier.disableFailedCategory,
              [NotificationIdentifier.tryAgainAction, UNNotificationDefaultActionIdentifier].contains(actionIdentifier)
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
    private let onRetryRequested: (Int) -> Void
    /// Notifications about an alias, so they can be withdrawn once it is disabled.
    private var aliasNotificationIdentifiers: [Int: Set<String>] = [:]

    init(
        center: any UserNotificationCenter = SystemNotificationCenter(),
        onDisableRequested: @escaping (Int) -> Void,
        onRetryRequested: @escaping (Int) -> Void
    ) {
        self.center = center
        self.onDisableRequested = onDisableRequested
        self.onRetryRequested = onRetryRequested
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
        let tryAgain = UNNotificationAction(identifier: NotificationIdentifier.tryAgainAction, title: "Try Again")
        let disableFailed = UNNotificationCategory(
            identifier: NotificationIdentifier.disableFailedCategory,
            actions: [tryAgain],
            intentIdentifiers: []
        )
        center.setNotificationCategories([mailReceived, disableFailed])
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ arrival: MailArrival, turnsOffAt: Date?) {
        deliver(NotificationContentFactory.content(for: arrival, turnsOffAt: turnsOffAt))
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
        if let aliasID = NotificationResponseRouter.aliasToDisable(
            categoryIdentifier: categoryIdentifier,
            actionIdentifier: actionIdentifier,
            userInfo: userInfo
        ) {
            await requestDisable(aliasID: aliasID)
        } else if let aliasID = NotificationResponseRouter.aliasToRetry(
            categoryIdentifier: categoryIdentifier,
            actionIdentifier: actionIdentifier,
            userInfo: userInfo
        ) {
            await requestRetry(aliasID: aliasID)
        }
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

    private func requestRetry(aliasID: Int) {
        onRetryRequested(aliasID)
    }

    private func deliver(_ content: NotificationContent) {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.subtitle = content.subtitle
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
