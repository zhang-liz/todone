import Foundation
import Testing
@testable import TodoneKit

@Suite struct NotificationPlannerTests {
    let cal: Calendar
    let now: Date
    let store: AppStore

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 10))!
        store = AppStore()
        store.calendar = cal
    }

    func at(_ hour: Int, day: Int = 24) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    func plan(notifyAtDueTime: Bool = true) -> [PlannedNotification] {
        NotificationPlanner.plan(tasks: store.tasks, reminders: store.reminders,
                                 notifyAtDueTime: notifyAtDueTime, now: now)
    }

    @Test func timedTaskGetsDueTimeNotificationWithoutReminder() {
        let t = store.addTask(title: "some task", dueDate: at(22), hasDueTime: true)
        let p = plan()
        #expect(p.count == 1)
        #expect(p[0].taskID == t.id)
        #expect(p[0].fireDate == at(22))
        #expect(p[0].id == "due-\(t.id.uuidString)")
    }

    @Test func allDayTaskGetsNoAutoNotification() {
        store.addTask(title: "all day", dueDate: at(0), hasDueTime: false)
        #expect(plan().isEmpty)
    }

    @Test func pastAndCompletedTasksSkipped() {
        store.addTask(title: "past", dueDate: at(9), hasDueTime: true)
        let done = store.addTask(title: "done", dueDate: at(22), hasDueTime: true)
        store.complete(done, now: now)
        #expect(plan().isEmpty)
    }

    @Test func settingOffDisablesAutoButKeepsReminders() {
        let t = store.addTask(title: "t", dueDate: at(22), hasDueTime: true)
        store.addReminder(taskID: t.id, kind: .relative(minutesBefore: 10))
        let p = plan(notifyAtDueTime: false)
        #expect(p.count == 1)
        #expect(p[0].fireDate == at(22).addingTimeInterval(-600))
    }

    @Test func explicitAtDueTimeReminderNotDuplicated() {
        let t = store.addTask(title: "t", dueDate: at(22), hasDueTime: true)
        let r = store.addReminder(taskID: t.id, kind: .relative(minutesBefore: 0))
        let p = plan()
        #expect(p.count == 1)
        #expect(p[0].id == r.id.uuidString)
    }

    @Test func absoluteReminderOnUndatedTaskFires() {
        let t = store.addTask(title: "t")
        store.addReminder(taskID: t.id, kind: .absolute(at(9, day: 25)))
        let p = plan()
        #expect(p.count == 1)
        #expect(p[0].fireDate == at(9, day: 25))
    }

    @Test func relativeReminderOnAllDayTaskSkipped() {
        let t = store.addTask(title: "t", dueDate: at(0), hasDueTime: false)
        store.addReminder(taskID: t.id, kind: .relative(minutesBefore: 10))
        #expect(plan().isEmpty)
    }
}
