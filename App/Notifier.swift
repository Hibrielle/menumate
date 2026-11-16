import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorizationOnce() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func showFailure(_ title: String, _ message: String) {
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "notify.actionFailedTitle"), title)
        content.body = String(message.prefix(200))
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 执行超过这个时长(秒)才发成功通知。
    static let successNoticeThreshold: TimeInterval = 10

    static func showSuccess(_ title: String, duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "notify.actionSucceededTitle"), title)
        content.body = String(format: String(localized: "notify.actionSucceededBody"), duration)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
