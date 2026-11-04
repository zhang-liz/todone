import Foundation
import Testing
@testable import TodoneKit

@Suite struct QuickAddRepeatTests {
    let cal: Calendar
    let parser: QuickAddParser

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        let now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))! // Wednesday
        parser = QuickAddParser(calendar: c, now: now)
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }


    @Test func monthDayLaterThisMonthIsNotSkipped() {
        #expect(parser.parse("rent every month on the 30th").dueDate == day(2026, 7, 30))
    }

    @Test func untilOnlyTakesItsOwnDate() {
        let r = parser.parse("gym every day with Sam until dec 1")
        #expect(r.title == "gym with Sam")
        #expect(r.recurrence?.endDate == day(2026, 12, 1))
    }

    @Test func aTimeAfterUntilStillApplies() {
        let r = parser.parse("gym every day until dec 1 at 7am")
        #expect(r.title == "gym")
        #expect(r.hasDueTime)
        #expect(r.dueDate == day(2026, 7, 23, 7))
        #expect(r.recurrence?.endDate == day(2026, 12, 1))
    }

    @Test func aTimeBeforeUntilStillApplies() {
        let r = parser.parse("standup every mon 5pm until dec 1")
        #expect(r.title == "standup")
        #expect(r.dueDate == day(2026, 7, 27, 17))
    }

    @Test func throughInATitleIsNotAnEndDate() {
        let r = parser.parse("read through emails every monday")
        #expect(r.title == "read through emails")
        #expect(r.recurrence?.weekdays == [2])
        #expect(r.recurrence?.endDate == nil)
    }

    @Test func aPastTimeStartsAtTheNextOccurrence() {
        #expect(parser.parse("gym every day 7am").dueDate == day(2026, 7, 23, 7))
        #expect(parser.parse("standup every wed 9am").dueDate == day(2026, 7, 29, 9))
    }
}
