import Foundation
import Testing
@testable import TodoneKit

@Suite struct ArchivedTaskTests {
    // Tasks in an archived project still showed in Today, counted in the badge and notified.
    @Test func archivedTasksLeaveTodayOverdueAndFilters() throws {
        let s = AppStore()
        let p = s.addProject(name: "Old")
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        s.addTask(title: "today", dueDate: now, projectID: p.id)
        s.addTask(title: "late", dueDate: yesterday, projectID: p.id)
        #expect(s.todayCount(now: now) == 2)

        s.archiveProject(p)

        #expect(s.todayCount(now: now) == 0)
        #expect(s.tasksDue(on: now).isEmpty)
        #expect(s.overdueTasks(now: now).isEmpty)
        #expect(s.tasksMatching(try FilterEngine.parse("today | overdue"), now: now).isEmpty)
    }

    @Test func archivedTasksDoNotNotify() {
        let s = AppStore()
        let p = s.addProject(name: "Old")
        let now = Date()
        s.addTask(title: "later", dueDate: now.addingTimeInterval(3600), hasDueTime: true, projectID: p.id)
        func planned() -> Int {
            NotificationPlanner.plan(tasks: s.incompleteTasks, reminders: s.reminders,
                                     notifyAtDueTime: true, now: now).count
        }
        #expect(planned() == 1)

        s.archiveProject(p)
        #expect(planned() == 0)

        s.archiveProject(p, archived: false)
        #expect(planned() == 1)
    }

    @Test func archivingTellsTheSchedulerToUpdate() {
        let s = AppStore()
        let p = s.addProject(name: "Old")
        var calls = 0
        s.onRemindersChanged = { calls += 1 }

        s.archiveProject(p)

        #expect(calls == 1)
    }
}
