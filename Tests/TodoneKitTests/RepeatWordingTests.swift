import Foundation
import Testing
@testable import TodoneKit

@Suite struct RepeatWordingTests {
    let cal: Calendar

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // "every other monday" stayed in the title as "every other" with a one-time date.
    @Test func everyOtherWeekday() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "Call every other monday", calendar: cal))
        #expect(rule.interval == 2)
        #expect(rule.weekdays == [2])
        #expect(rule.displayText == "every other mon")
        // Jul 27 2026 is a Monday.
        #expect(rule.nextOccurrence(after: day(2026, 7, 27), calendar: cal) == day(2026, 8, 10))
    }

    @Test func storedFormReadsBackTheSame() throws {
        for text in ["every other mon", "every 3 fri", "every! other tue",
                     "every month on the last day", "every 2 months on the last day"] {
            let rule = try #require(RecurrenceRule.deserialize(text, calendar: cal))
            #expect(rule.displayText == text)
        }
    }

    @Test func everyThreeFridaysKeepsTheDayAndGap() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every 3 fridays", calendar: cal))
        #expect(rule.nextOccurrence(after: day(2026, 7, 24), calendar: cal) == day(2026, 8, 14))
    }

    @Test func quickAddStartsOnTheNearestMatchingDay() {
        // Wednesday, Jul 22 2026.
        let parser = QuickAddParser(calendar: cal, now: day(2026, 7, 22, 10))
        let r = parser.parse("Call every other monday")
        #expect(r.title == "Call")
        #expect(r.dueDate == day(2026, 7, 27))
    }

    @Test func lastDayOfTheMonth() throws {
        for text in ["every month on the last day", "every last day", "every last day of the month"] {
            let (rule, _) = try #require(RecurrenceRule.parse(from: text, calendar: cal))
            #expect(rule.displayText == "every month on the last day")
            #expect(rule.nextOccurrence(after: day(2026, 1, 31), calendar: cal) == day(2026, 2, 28))
            #expect(rule.nextOccurrence(after: day(2026, 2, 28), calendar: cal) == day(2026, 3, 31))
        }
    }

    @Test func quickAddLastDayLeavesTheTitleClean() {
        let parser = QuickAddParser(calendar: cal, now: day(2026, 7, 22, 10))
        let r = parser.parse("Pay rent every month on the last day")
        #expect(r.title == "Pay rent")
        #expect(r.dueDate == day(2026, 7, 31))
    }

    @Test func plainWeekdayRulesAreUnchanged() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every monday", calendar: cal))
        #expect(rule.interval == 1)
        #expect(rule.nextOccurrence(after: day(2026, 7, 27), calendar: cal) == day(2026, 8, 3))
    }
}
