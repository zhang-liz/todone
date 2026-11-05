import Foundation
import Testing
@testable import TodoneKit

@Suite struct RescheduleManyTests {
    let cal: Calendar
    let now: Date

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!
    }

    // "Reschedule all to Today" and bulk "Due Today" removed due times.
    // Moving one task by drag kept them.
    @Test func keepsDueTimesAndAllDayTasks() {
        let s = AppStore()
        s.calendar = cal
        let timed = s.addTask(title: "timed", dueDate: cal.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 15, minute: 30)),
                              hasDueTime: true)
        let allDay = s.addTask(title: "all day", dueDate: cal.date(from: DateComponents(year: 2026, month: 7, day: 20)))

        s.reschedule([timed, allDay], toDay: now)

        #expect(timed.dueDate == cal.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 15, minute: 30)))
        #expect(timed.hasDueTime)
        #expect(allDay.dueDate == cal.startOfDay(for: now))
        #expect(!allDay.hasDueTime)
    }

    @Test func isOneUndoStep() {
        let s = AppStore()
        s.calendar = cal
        let old = cal.date(from: DateComponents(year: 2026, month: 7, day: 20))
        let tasks = (0..<60).map { s.addTask(title: "t\($0)", dueDate: old) }

        s.reschedule(tasks, toDay: now)
        #expect(s.task(tasks[59].id)?.dueDate == cal.startOfDay(for: now))

        s.undo()
        #expect(s.incompleteTasks.count == 60)
        #expect(s.incompleteTasks.allSatisfy { $0.dueDate == old })
    }
}
