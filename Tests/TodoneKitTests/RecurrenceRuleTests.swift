import Foundation
import Testing
@testable import TodoneKit

@Suite struct RecurrenceRuleTests {
    let cal: Calendar

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Parsing

    @Test func everyDay() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "water plants every day"))
        #expect(rule.unit == .day)
        #expect(rule.interval == 1)
        #expect(!rule.strict)
        #expect(rule.displayText == "every day")
    }

    @Test func everyTwoWeeks() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every 2 weeks"))
        #expect(rule.unit == .week)
        #expect(rule.interval == 2)
        #expect(rule.displayText == "every 2 weeks")
    }

    @Test func everyOtherDay() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every other day"))
        #expect(rule.unit == .day)
        #expect(rule.interval == 2)
    }

    @Test func everyWeekdayList() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "standup every mon, fri"))
        #expect(rule.unit == .week)
        #expect(rule.weekdays == [2, 6]) // Mon, Fri
    }

    @Test func everyWorkday() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every workday"))
        #expect(rule.weekdays == [2, 3, 4, 5, 6])
    }

    @Test func everyMonthOnThe15th() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "rent every month on the 15th"))
        #expect(rule.unit == .month)
        #expect(rule.monthDay == 15)
    }

    @Test func strictVariant() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every! 3 days"))
        #expect(rule.strict)
        #expect(rule.interval == 3)
    }

    @Test func serializationRoundTrip() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every mon, fri"))
        let restored = try #require(RecurrenceRule.deserialize(rule.displayText))
        #expect(restored == rule)
    }

    @Test func noRecurrenceReturnsNil() {
        #expect(RecurrenceRule.parse(from: "buy milk tomorrow") == nil)
    }

    // MARK: Next occurrence

    @Test func nextDaily() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every day"))
        let next = rule.nextOccurrence(after: day(2026, 7, 22, 9), calendar: cal)
        #expect(next == day(2026, 7, 23, 9)) // time preserved
    }

    @Test func nextEveryThreeDays() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every 3 days"))
        #expect(rule.nextOccurrence(after: day(2026, 7, 22), calendar: cal) == day(2026, 7, 25))
    }

    @Test func nextWeekly() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every week"))
        #expect(rule.nextOccurrence(after: day(2026, 7, 22), calendar: cal) == day(2026, 7, 29))
    }

    @Test func nextWeekdayList() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every mon, fri"))
        // From Wednesday Jul 22 → Friday Jul 24.
        #expect(rule.nextOccurrence(after: day(2026, 7, 22), calendar: cal) == day(2026, 7, 24))
        // From Friday Jul 24 → Monday Jul 27.
        #expect(rule.nextOccurrence(after: day(2026, 7, 24), calendar: cal) == day(2026, 7, 27))
    }

    @Test func nextMonthly() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month"))
        #expect(rule.nextOccurrence(after: day(2026, 7, 31), calendar: cal) == day(2026, 8, 31))
    }

    @Test func monthlyOnDayClampsShortMonths() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month on the 31st"))
        // Jan 31 → Feb: clamps to Feb 28 (2027 not a leap year).
        let next = rule.nextOccurrence(after: day(2027, 1, 31), calendar: cal)
        #expect(next == day(2027, 2, 28))
    }

    @Test func nextYearly() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every year"))
        #expect(rule.nextOccurrence(after: day(2026, 7, 22), calendar: cal) == day(2027, 7, 22))
    }
}
