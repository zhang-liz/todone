import AppKit
import Foundation
import TodoneKit
import UserNotifications

/// Schedules local notifications for task reminders and keeps the Dock badge
/// in sync. Gracefully no-ops when notification permission is unavailable
/// (e.g. running outside an app bundle).
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private weak var store: AppStore?
    private var authorized = false
    private var available: Bool = {
        // UNUserNotificationCenter requires a proper bundle identifier.
        Bundle.main.bundleIdentifier != nil
    }()

    func attach(store: AppStore) {
        self.store = store
        store.onRemindersChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.rescheduleAll()
                self?.refreshBadge()
            }
        }
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
            DispatchQueue.main.async {
                self?.rescheduleAll()
                self?.refreshBadge()
            }
        }
    }

    func rescheduleAll() {
        guard available, authorized, let store else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for reminder in store.reminders {
            guard let task = store.task(reminder.taskID), !task.isCompleted else { continue }
            let fireDate: Date?
            switch reminder.kind {
            case .absolute(let date):
                fireDate = date
            case .relative(let minutes):
                guard let due = task.dueDate, task.hasDueTime else { continue }
                fireDate = due.addingTimeInterval(TimeInterval(-minutes * 60))
            }
            guard let fire = fireDate, fire > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            if let project = store.project(task.projectID) {
                content.subtitle = project.isInbox ? "Inbox" : project.name
            }
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: reminder.id.uuidString,
                                             content: content, trigger: trigger))
        }
    }

    func refreshBadge() {
        guard let store else { return }
        let enabled = UserDefaults.standard.object(forKey: "badgeCount") as? Bool ?? true
        let count = enabled ? store.todayCount() : 0
        DispatchQueue.main.async {
            NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
        }
    }
}
