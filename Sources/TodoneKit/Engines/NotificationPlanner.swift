import Foundation

/// One local notification the app should have pending.
public struct PlannedNotification: Equatable, Sendable {
    /// Stable identifier: the reminder's UUID, or `due-<taskID>` for the
    /// automatic due-time notification.
    public let id: String
    public let taskID: UUID
    public let fireDate: Date

    public init(id: String, taskID: UUID, fireDate: Date) {
        self.id = id
        self.taskID = taskID
        self.fireDate = fireDate
    }
}

/// Pure planning of which notifications should be pending, so the schedule
/// can be unit-tested without UserNotifications.
public enum NotificationPlanner {
    /// - Parameters:
    ///   - notifyAtDueTime: when true, every open task with a due *time* gets a
    ///     notification at that time even if the user added no reminder.
    public static func plan(tasks: [TodoTask], reminders: [TaskReminder],
                            notifyAtDueTime: Bool, now: Date) -> [PlannedNotification] {
        var byID: [UUID: TodoTask] = [:]
        for task in tasks { byID[task.id] = task }

        var planned: [PlannedNotification] = []
        var coveredAtDueTime = Set<UUID>()

        for reminder in reminders {
            guard let task = byID[reminder.taskID], !task.isCompleted else { continue }
            let fire: Date
            switch reminder.kind {
            case .absolute(let date):
                fire = date
            case .relative(let minutes):
                guard let due = task.dueDate, task.hasDueTime else { continue }
                fire = due.addingTimeInterval(TimeInterval(-minutes * 60))
                if minutes == 0 { coveredAtDueTime.insert(task.id) }
            }
            guard fire > now else { continue }
            planned.append(PlannedNotification(id: reminder.id.uuidString, taskID: task.id, fireDate: fire))
        }

        guard notifyAtDueTime else { return planned }

        for task in tasks where !task.isCompleted && task.hasDueTime {
            guard let due = task.dueDate, due > now, !coveredAtDueTime.contains(task.id) else { continue }
            planned.append(PlannedNotification(id: "due-\(task.id.uuidString)", taskID: task.id, fireDate: due))
        }
        return planned
    }
}
