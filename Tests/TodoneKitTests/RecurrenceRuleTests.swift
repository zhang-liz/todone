import Foundation
import Testing
@testable import TodoneKit

@Suite struct RecurrenceRuleTests {
    let cal: Calendar
    let now: Date

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!
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

    // "on the 32nd" used to be consumed as a valid token and silently degrade to
    // a plain "every month", losing the day the user asked for.
    @Test func outOfRangeMonthDayIsNotConsumed() {
        #expect(RecurrenceRule.parse(from: "every month on the 32nd") == nil)
        #expect(RecurrenceRule.parse(from: "every month on the 0th") == nil)
    }

    @Test func validMonthDayBoundariesStillParse() throws {
        let (first, _) = try #require(RecurrenceRule.parse(from: "every month on the 1st"))
        #expect(first.monthDay == 1)
        let (last, _) = try #require(RecurrenceRule.parse(from: "every month on the 31st"))
        #expect(last.monthDay == 31)
    }

    @Test func monthlyAnchorKeepsSeconds() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month on the 15th"))
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15,
                                                 hour: 9, minute: 30, second: 45))!
        let next = try #require(rule.nextOccurrence(after: base, calendar: cal))
        #expect(cal.component(.second, from: next) == 45)
        #expect(cal.component(.minute, from: next) == 30)
        #expect(cal.component(.hour, from: next) == 9)
        #expect(cal.component(.day, from: next) == 15)
        #expect(cal.component(.month, from: next) == 2)
    }

    // The month-day pattern hardcoded "month", so an interval fell through to
    // the generic branch and the requested day was silently dropped.
    @Test func intervalMonthlyOnADayKeepsBoth() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every 2 months on the 3rd", calendar: cal))
        #expect(rule.interval == 2)
        #expect(rule.unit == .month)
        #expect(rule.monthDay == 3)

        let next = try #require(rule.nextOccurrence(after: day(2026, 1, 3), calendar: cal))
        #expect(next == day(2026, 3, 3))
    }

    @Test func plainMonthlyOnADayStillParses() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month on the 15th", calendar: cal))
        #expect(rule.interval == 1)
        #expect(rule.monthDay == 15)
        #expect(rule.displayText == "every month on the 15th")
    }

    // MARK: End dates

    @Test func untilClauseBoundsTheSeries() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every day until dec 1", calendar: cal, now: now))
        #expect(rule.unit == .day)
        #expect(rule.endDate == day(2026, 12, 1))

        // Inside the window it advances as usual.
        #expect(rule.nextOccurrence(after: day(2026, 11, 29), calendar: cal) == day(2026, 11, 30))
        // The last day itself is allowed.
        #expect(rule.nextOccurrence(after: day(2026, 11, 30), calendar: cal) == day(2026, 12, 1))
        // Past it, the series is over.
        #expect(rule.nextOccurrence(after: day(2026, 12, 1), calendar: cal) == nil)
    }

    @Test func untilSurvivesSerializationRoundTrip() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every week until dec 1", calendar: cal, now: now))
        let restored = try #require(RecurrenceRule.deserialize(rule.displayText, calendar: cal))
        #expect(restored.endDate == rule.endDate)
        #expect(restored.unit == .week)
    }

    @Test func unparseableUntilTailIsLeftAlone() throws {
        // "until further notice" is not a date; the recurrence still parses and
        // the phrase stays in the title rather than becoming a bogus end date.
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every day until further notice", calendar: cal, now: now))
        #expect(rule.endDate == nil)
        #expect(rule.unit == .day)
    }

    @Test func recurrenceWithoutUntilHasNoEndDate() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every 3 days", calendar: cal))
        #expect(rule.endDate == nil)
    }
}
