import Foundation
import Testing
@testable import TodoneKit

@Suite struct QuickAddParserTests {
    let cal: Calendar
    let now: Date
    let parser: QuickAddParser

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))! // Wednesday
        parser = QuickAddParser(calendar: cal, now: now)
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func plainTitle() {
        let r = parser.parse("Buy milk")
        #expect(r.title == "Buy milk")
        #expect(r.dueDate == nil)
        #expect(r.priority == .p4)
        #expect(r.tokens.isEmpty)
    }

    @Test func kitchenSink() {
        let r = parser.parse("Pay rent tomorrow 5pm p1 #Finance /Bills @home @money")
        #expect(r.title == "Pay rent")
        #expect(r.dueDate == day(2026, 7, 23, 17))
        #expect(r.hasDueTime)
        #expect(r.priority == .p1)
        #expect(r.projectName == "Finance")
        #expect(r.sectionName == "Bills")
        #expect(r.labelNames == ["home", "money"])
    }

    @Test func quotedProjectName() {
        let r = parser.parse("Plan trip #\"Summer Vacation\"")
        #expect(r.projectName == "Summer Vacation")
        #expect(r.title == "Plan trip")
    }

    @Test func recurrenceWithWeekdays() throws {
        let r = parser.parse("Standup every mon, fri")
        let rule = try #require(r.recurrence)
        #expect(rule.weekdays == [2, 6])
        #expect(r.title == "Standup")
        // No explicit start date: first occurrence is next matching weekday (Fri Jul 24).
        #expect(r.dueDate == day(2026, 7, 24))
    }

    @Test func recurrenceDefaultsToToday() {
        let r = parser.parse("Water plants every day")
        #expect(r.dueDate == day(2026, 7, 22))
        #expect(r.recurrence?.displayText == "every day")
    }

    @Test func recurrenceNotEatenByDateParser() throws {
        // "every mon" must become recurrence, not a plain Monday due date.
        let r = parser.parse("Report every mon")
        #expect(r.recurrence != nil)
        #expect(r.title == "Report")
    }

    @Test func priorityRequiresWordBoundary() {
        let r = parser.parse("Fix p1ng issue")
        #expect(r.priority == .p4)
        #expect(r.title == "Fix p1ng issue")
    }

    @Test func hashInsideWordIsNotAProject() {
        let r = parser.parse("Learn C# basics")
        #expect(r.projectName == nil)
        #expect(r.title == "Learn C# basics")
    }

    @Test func labelCreatesNoDuplicates() {
        let r = parser.parse("Task @home @home")
        #expect(r.labelNames == ["home"])
    }

    @Test func disabledRangeIsIgnored() {
        let input = "Pay rent tomorrow"
        let first = parser.parse(input)
        let dateToken = first.tokens.first { $0.kind == .date }!
        let second = parser.parse(input, disabledRanges: [dateToken.range])
        #expect(second.dueDate == nil)
        #expect(second.title == "Pay rent tomorrow")
    }

    @Test func tokensSortedByLocation() {
        let r = parser.parse("a p1 tomorrow #P @l")
        let locations = r.tokens.map(\.range.location)
        #expect(locations == locations.sorted())
    }

    // A bare time supplies a date, which used to suppress the weekday alignment
    // and start weekday rules on whatever day the time landed on.
    @Test func weekdayRuleWithTimeStartsOnMatchingWeekday() {
        // now = Wednesday Jul 22 2026.
        let r = parser.parse("standup every mon 5pm")
        #expect(r.dueDate == day(2026, 7, 27, 17))  // the following Monday
        #expect(r.hasDueTime)
    }

    @Test func workdayRuleWithTimeSkipsTheWeekend() {
        let sat = cal.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 10))!
        let satParser = QuickAddParser(calendar: cal, now: sat)

        let r = satParser.parse("gym every workday at 7am")
        #expect(r.dueDate == day(2026, 7, 27, 7))   // Monday, not Sunday
    }

    @Test func weekdayRuleWithTimeKeepsTodayWhenTodayMatches() {
        // Wednesday rule parsed on a Wednesday, before the stated time.
        let r = parser.parse("standup every wed 5pm")
        #expect(r.dueDate == day(2026, 7, 22, 17))
    }

    @Test func explicitDateStillWinsOverWeekdayAlignment() {
        let r = parser.parse("standup every mon jul 24 5pm")
        #expect(r.dueDate == day(2026, 7, 24, 17))
    }

    @Test func monthDayRuleWithoutDateStartsOnThatDay() {
        // now = Jul 22; the 15th has passed, so the next one is Aug 15.
        let r = parser.parse("rent every month on the 15th")
        #expect(r.dueDate == day(2026, 8, 15))
    }

    @Test func monthDayRuleWithTimeStartsOnThatDay() {
        let r = parser.parse("review every month on the 15th at 9am")
        #expect(r.dueDate == day(2026, 8, 15, 9))
        #expect(r.hasDueTime)
    }
}
