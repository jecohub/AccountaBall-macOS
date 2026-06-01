import AppKit
import UserNotifications

class NotificationService {
    func requestPermission() async {
        guard NSApp != nil else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        )
    }

    func sendOffTaskNudge(task: String) {
        guard NSApp != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Hey, get back on track!"
        content.body = "You said you'd \(task.prefix(60))…"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "off-task-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
