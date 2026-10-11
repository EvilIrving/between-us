import Foundation
import UserNotifications

enum NotificationAuthorizationState: String, Sendable {
    case enabled
    case disabled
    case notDetermined
}

actor NotificationManager {
    private let center = UNUserNotificationCenter.current()

    func authorizationState() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .enabled
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notifyNewItem(kind: ContainerKind) async {
        guard await authorizationState() == .enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = T("耳语")
        switch kind {
        case .star: content.body = T("星星瓶里多了一颗星星。")
        case .capsule: content.body = T("胶囊瓶里多了一颗胶囊。")
        case .paper: content.body = T("纸团篓里多了一个纸团。")
        }
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(
                identifier: "new-item-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    func notifyOpened(kind: ContainerKind) async {
        guard await authorizationState() == .enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = T("耳语")
        switch kind {
        case .star: content.body = T("对方打开了你放入的星星。")
        case .capsule: content.body = T("对方打开了你放入的胶囊。")
        case .paper: content.body = T("对方展开了你放入的纸团。")
        }
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(
                identifier: "opened-item-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }
}


@MainActor
final class CloudKitPushBroker {
    static let shared = CloudKitPushBroker()

    private var handler: (() async -> Void)?
    private var hasPendingPush = false

    private init() {}

    func install(handler: @escaping () async -> Void) {
        self.handler = handler
        guard hasPendingPush else { return }
        hasPendingPush = false
        Task { await handler() }
    }

    func receive() async -> Bool {
        guard let handler else {
            hasPendingPush = true
            return false
        }
        await handler()
        return true
    }
}

extension Notification.Name {
    static let betweenUsSharingFailed = Notification.Name("BetweenUsSharingFailed")
    static let betweenUsSharingStopped = Notification.Name("BetweenUsSharingStopped")
}
