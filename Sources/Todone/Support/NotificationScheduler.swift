import AppKit
import Foundation
import Observation
import TodoneKit
import UserNotifications

/// Schedules local notifications for task due times and reminders, and keeps
/// the Dock badge in sync. Gracefully no-ops when notification permission is
/// unavailable (e.g. running outside an app bundle).
@Observable
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    static let notifyAtDueTimeKey = "notifyAtDueTime"

    /// macOS keeps at most 64 pending local notifications per app.
    private static let pendingLimit = 64

    /// Current system permission, refreshed on attach and on demand.
    private(set) var status: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private weak var store: AppStore?
    private let available: Bool = {
        // UNUserNotificationCenter requires a proper bundle identifier.
        Bundle.main.bundleIdentifier != nil
    }()

    private var authorized: Bool {
        status == .authorized || status == .provisional
    }

    static var notifyAtDueTime: Bool {
        UserDefaults.standard.object(forKey: notifyAtDueTimeKey) as? Bool ?? true
    }

    func attach(store: AppStore) {
        self.store = store
        store.onRemindersChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.rescheduleAll()
                self?.refreshBadge()
            }
        }
        guard available else { return }
        requestAuthorization()
    }

    /// Ask macOS for permission (prompts only the first time), then reschedule.
    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] _, _ in
            self?.refreshAuthorization()
        }
    }

    /// Re-read the system permission and reschedule if it changed.
    func refreshAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = settings.authorizationStatus
                self.rescheduleAll()
                self.refreshBadge()
            }
        }
    }

    /// Open the Notifications pane so the user can turn Todone back on.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func rescheduleAll() {
        guard available, authorized, let store else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let planned = NotificationPlanner.plan(tasks: store.tasks, reminders: store.reminders,
                                               notifyAtDueTime: Self.notifyAtDueTime, now: Date())
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.pendingLimit)

        for item in planned {
            guard let task = store.task(item.taskID) else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            if let project = store.project(task.projectID) {
                content.subtitle = project.isInbox ? "Inbox" : project.name
            }
            if let due = task.dueDate, task.hasDueTime {
                content.body = "Due " + due.formatted(date: .omitted, time: .shortened)
            }
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
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
