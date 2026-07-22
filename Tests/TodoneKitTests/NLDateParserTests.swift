import Foundation
import Testing
@testable import TodoneKit

// Fixed "now": Wednesday 2026-07-22 10:00 local time.
private func makeNow() -> (Calendar, Date) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!
    return (cal, now)
}

@Suite struct NLDateParserTests {
    let cal: Calendar
    let now: Date
    let parser: NLDateParser

    init() {
        (cal, now) = makeNow()
        parser = NLDateParser(calendar: cal, now: now)
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int? = nil, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h ?? 0, minute: h != nil ? min : 0))!
    }

    @Test func today() throws {
        let r = try #require(parser.parse("buy milk today"))
        #expect(r.date == day(2026, 7, 22))
        #expect(!r.hasTime)
    }

    @Test func tomorrow() throws {
        let r = try #require(parser.parse("tomorrow"))
        #expect(r.date == day(2026, 7, 23))
    }

    @Test func tomAbbreviation() throws {
        let r = try #require(parser.parse("call mom tom"))
        #expect(r.date == day(2026, 7, 23))
    }

    @Test func bareWeekdayIsStrictlyAfterToday() throws {
        // Now is Wednesday; "wednesday" should be NEXT Wednesday.
        let r = try #require(parser.parse("wednesday"))
        #expect(r.date == day(2026, 7, 29))
    }

    @Test func fridayThisWeek() throws {
        let r = try #require(parser.parse("gym friday"))
        #expect(r.date == day(2026, 7, 24))
    }

    @Test func nextMonday() throws {
        let r = try #require(parser.parse("next monday"))
        #expect(r.date == day(2026, 7, 27))
    }

    @Test func monthNameDay() throws {
        let r = try #require(parser.parse("dentist jul 30"))
        #expect(r.date == day(2026, 7, 30))
    }

    @Test func monthNameDayRollsToNextYear() throws {
        // Jan 5 already passed this year.
        let r = try #require(parser.parse("jan 5"))
        #expect(r.date == day(2027, 1, 5))
    }

    @Test func dayMonthName() throws {
        let r = try #require(parser.parse("30 jul"))
        #expect(r.date == day(2026, 7, 30))
    }

    @Test func explicitYear() throws {
        let r = try #require(parser.parse("july 30 2027"))
        #expect(r.date == day(2027, 7, 30))
    }

    @Test func numericSlash() throws {
        let r = try #require(parser.parse("8/15"))
        #expect(r.date == day(2026, 8, 15))
    }

    @Test func inThreeDays() throws {
        let r = try #require(parser.parse("in 3 days"))
        #expect(r.date == day(2026, 7, 25))
    }

    @Test func inTwoWeeks() throws {
        let r = try #require(parser.parse("in 2 weeks"))
        #expect(r.date == day(2026, 8, 5))
    }

    @Test func dateWithTime() throws {
        let r = try #require(parser.parse("meeting tomorrow 3pm"))
        #expect(r.date == day(2026, 7, 23, 15))
        #expect(r.hasTime)
    }

    @Test func timeWithMinutes() throws {
        let r = try #require(parser.parse("tomorrow at 3:30pm"))
        #expect(r.date == day(2026, 7, 23, 15, 30))
        #expect(r.hasTime)
    }

    @Test func twentyFourHourTime() throws {
        let r = try #require(parser.parse("friday 15:00"))
        #expect(r.date == day(2026, 7, 24, 15))
        #expect(r.hasTime)
    }

    @Test func bareTimeFutureIsToday() throws {
        // Now is 10:00, so 3pm is later today.
        let r = try #require(parser.parse("3pm"))
        #expect(r.date == day(2026, 7, 22, 15))
        #expect(r.hasTime)
    }

    @Test func bareTimePastRollsToTomorrow() throws {
        let r = try #require(parser.parse("9am"))
        #expect(r.date == day(2026, 7, 23, 9))
    }

    @Test func noonAndMidnightAmPm() throws {
        let noon = try #require(parser.parse("tomorrow 12pm"))
        #expect(noon.date == day(2026, 7, 23, 12))
        let midnight = try #require(parser.parse("tomorrow 12am"))
        #expect(midnight.date == day(2026, 7, 23, 0))
    }

    @Test func nextWeekIsMonday() throws {
        let r = try #require(parser.parse("next week"))
        #expect(r.date == day(2026, 7, 27))
    }

    @Test func noDateReturnsNil() {
        #expect(parser.parse("just some words") == nil)
    }

    @Test func mayWithoutDayNumberIsNotADate() {
        // "may" as a plain verb shouldn't parse as a month.
        #expect(parser.parse("this may work") == nil)
    }

    @Test func rangesCoverMatchedText() throws {
        let input = "meeting tomorrow 3pm"
        let r = try #require(parser.parse(input))
        let ns = input as NSString
        let texts = r.ranges.map { ns.substring(with: $0) }
        #expect(texts.contains("tomorrow"))
        #expect(texts.contains("3pm"))
    }
}
