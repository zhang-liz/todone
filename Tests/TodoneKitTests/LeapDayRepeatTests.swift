import Foundation
import Testing
@testable import TodoneKit

@Suite struct LeapDayRepeatTests {
    let cal: Calendar

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // After one short year, a Feb 29 task stayed on Feb 28 forever.
    @Test func yearlyFeb29ReturnsInALeapYear() {
        let s = AppStore()
        s.calendar = cal
        let t = s.addTask(title: "Birthday", dueDate: day(2028, 2, 29), recurrence: "every year")

        for expected in [day(2029, 2, 28), day(2030, 2, 28), day(2031, 2, 28), day(2032, 2, 29)] {
            s.complete(t, now: t.dueDate!)
            #expect(t.dueDate == expected)
        }
    }

    @Test func otherYearlyDatesStayPut() {
        let s = AppStore()
        s.calendar = cal
        let t = s.addTask(title: "Renew", dueDate: day(2027, 2, 28), recurrence: "every year")

        for expected in [day(2028, 2, 28), day(2029, 2, 28)] {
            s.complete(t, now: t.dueDate!)
            #expect(t.dueDate == expected)
        }
    }

    @Test func movingTheTaskStartsANewSeries() {
        let s = AppStore()
        s.calendar = cal
        let t = s.addTask(title: "Birthday", dueDate: day(2028, 2, 29), recurrence: "every year")
        s.updateTask(t) { $0.dueDate = day(2031, 2, 28) }

        s.complete(t, now: t.dueDate!)

        #expect(t.dueDate == day(2032, 2, 28))
    }
}
