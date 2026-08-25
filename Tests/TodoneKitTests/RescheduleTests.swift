import Foundation
import Testing
@testable import TodoneKit

@Suite struct RescheduleTests {
    let cal: Calendar
    let store: AppStore

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        store = AppStore()
        store.calendar = cal
    }

    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    @Test func timedTaskKeepsItsTimeOnNewDay() {
        let t = store.addTask(title: "call", dueDate: at(24, 22), hasDueTime: true)
        store.reschedule(t, toDay: at(25, 9, 30)) // time-of-day of the target is ignored
        #expect(t.dueDate == at(25, 22))
        #expect(t.hasDueTime)
    }

    @Test func allDayTaskLandsOnStartOfDay() {
        let t = store.addTask(title: "plan", dueDate: at(24), hasDueTime: false)
        store.reschedule(t, toDay: at(26, 15))
        #expect(t.dueDate == at(26))
        #expect(!t.hasDueTime)
    }

    @Test func undatedTaskGetsAllDayDate() {
        let t = store.addTask(title: "someday")
        store.reschedule(t, toDay: at(30, 8))
        #expect(t.dueDate == at(30))
        #expect(!t.hasDueTime)
    }

    @Test func nilClearsDateTimeAndRecurrence() {
        let t = store.addTask(title: "gym", dueDate: at(24, 7), hasDueTime: true, recurrence: "every day")
        store.reschedule(t, toDay: nil)
        #expect(t.dueDate == nil)
        #expect(!t.hasDueTime)
        #expect(t.recurrence == nil)
    }

    @Test func movingDayKeepsRecurrenceAndIsUndoable() {
        let t = store.addTask(title: "gym", dueDate: at(24, 7), hasDueTime: true, recurrence: "every day")
        store.reschedule(t, toDay: at(25))
        #expect(t.recurrence == "every day")
        #expect(t.dueDate == at(25, 7))
        store.undo()
        #expect(store.task(t.id)?.dueDate == at(24, 7))
    }
}
