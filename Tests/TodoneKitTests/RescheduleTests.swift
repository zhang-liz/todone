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

@Suite struct DueTimeTests {
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

    @Test func setTimeKeepsDayChangesClock() {
        let t = store.addTask(title: "call", dueDate: at(24, 22), hasDueTime: true)
        store.setDueTime(t, to: at(1, 9, 15)) // only hour/minute of this date matter
        #expect(t.dueDate == at(24, 9, 15))
        #expect(t.hasDueTime)
    }

    @Test func setTimeOnAllDayTaskAddsTime() {
        let t = store.addTask(title: "plan", dueDate: at(24), hasDueTime: false)
        store.setDueTime(t, to: at(1, 14, 30))
        #expect(t.dueDate == at(24, 14, 30))
        #expect(t.hasDueTime)
    }

    @Test func setTimeOnUndatedTaskUsesToday() {
        let t = store.addTask(title: "x")
        store.setDueTime(t, to: at(1, 8), now: at(24, 12))
        #expect(t.dueDate == at(24, 8))
        #expect(t.hasDueTime)
    }

    @Test func clearTimeMakesAllDay() {
        let t = store.addTask(title: "call", dueDate: at(24, 22), hasDueTime: true)
        store.setDueTime(t, to: nil)
        #expect(t.dueDate == at(24))
        #expect(!t.hasDueTime)
    }

    @Test func defaultTimeIsNextFullHourToday() {
        let t = store.addTask(title: "x", dueDate: at(24), hasDueTime: false)
        store.addDefaultDueTime(t, now: at(24, 21, 5))
        #expect(t.dueDate == at(24, 22))
        #expect(t.hasDueTime)
    }

    @Test func defaultTimeIsNineOnOtherDays() {
        let t = store.addTask(title: "x", dueDate: at(30), hasDueTime: false)
        store.addDefaultDueTime(t, now: at(24, 21, 5))
        #expect(t.dueDate == at(30, 9))
    }

    @Test func defaultTimeLateTonightCapsAtElevenPM() {
        let t = store.addTask(title: "x", dueDate: at(24), hasDueTime: false)
        store.addDefaultDueTime(t, now: at(24, 23, 30))
        #expect(t.dueDate == at(24, 23))
    }
}
