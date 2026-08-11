import Foundation
import UserNotifications

/// Local notifications only — no server, no push, consistent with the rest
/// of the app. Schedules a single reminder ~90 days before an item's
/// `expiresAt`, only for items that just *expire* (passport, license,
/// insurance) rather than delete themselves — a temporary/disposable item
/// (§ expiration metadata, "hotel key code") gets silently swept on next
/// unlock instead (QuickVarStore.reload), no reminder needed for those.
///
/// Security invariant #2 says plaintext values never appear in notifications;
/// in the same spirit this keeps the item's *name* out of the notification
/// body too, since a lock-screen banner is a less trusted surface than the
/// in-app list — "Something you saved is expiring soon" costs little and
/// avoids leaking which specific record exists before authentication.
enum ExpirationNotifier {
    private static let leadTime: TimeInterval = 90 * 24 * 60 * 60

    static func scheduleReminder(for id: UUID, expiresAt: Date) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let reminderDate = max(Date().addingTimeInterval(60), expiresAt.addingTimeInterval(-leadTime))

            let content = UNMutableNotificationContent()
            content.title = "QuickVars"
            content.body = "Something you saved is expiring soon — open QuickVars to check."
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelReminder(for id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
