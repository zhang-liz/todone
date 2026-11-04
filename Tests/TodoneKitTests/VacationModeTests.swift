import Foundation
import Testing
@testable import TodoneKit

@Suite struct VacationModeTests {
    let cal: Calendar

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func complete(_ s: inout KarmaState, on date: Date) {
        KarmaEngine.applyCompletion(state: &s, date: date, completedToday: s.dailyGoal,
                                    completedThisWeek: s.weeklyGoal, calendar: cal)
    }

    // The setting says "freeze streaks", but the first completion after a break reset them.
    @Test func dailyStreakContinuesAfterVacation() {
        var s = KarmaState()
        complete(&s, on: day(2026, 7, 1, 9))
        complete(&s, on: day(2026, 7, 2, 9))
        #expect(s.currentDailyStreak == 2)

        KarmaEngine.setVacationMode(true, state: &s, now: day(2026, 7, 3, 9), calendar: cal)
        KarmaEngine.reconcileStreaks(state: &s, now: day(2026, 7, 10, 9), calendar: cal)
        KarmaEngine.setVacationMode(false, state: &s, now: day(2026, 7, 20, 9), calendar: cal)
        KarmaEngine.reconcileStreaks(state: &s, now: day(2026, 7, 20, 9), calendar: cal)
        #expect(s.currentDailyStreak == 2)
        #expect(s.vacationStartDay == nil)

        complete(&s, on: day(2026, 7, 20, 10))
        #expect(s.currentDailyStreak == 3)
    }

    @Test func weeklyStreakContinuesAfterVacation() {
        var s = KarmaState()
        complete(&s, on: day(2026, 7, 1, 9))
        complete(&s, on: day(2026, 7, 8, 9))
        #expect(s.currentWeeklyStreak == 2)

        KarmaEngine.setVacationMode(true, state: &s, now: day(2026, 7, 9, 9), calendar: cal)
        KarmaEngine.setVacationMode(false, state: &s, now: day(2026, 8, 5, 9), calendar: cal)
        KarmaEngine.reconcileStreaks(state: &s, now: day(2026, 8, 5, 9), calendar: cal)
        #expect(s.currentWeeklyStreak == 2)

        complete(&s, on: day(2026, 8, 5, 10))
        #expect(s.currentWeeklyStreak == 3)
    }

    @Test func aStreakAlreadyBrokenStaysBroken() {
        var s = KarmaState()
        complete(&s, on: day(2026, 7, 1, 9))

        KarmaEngine.setVacationMode(true, state: &s, now: day(2026, 7, 5, 9), calendar: cal)
        KarmaEngine.setVacationMode(false, state: &s, now: day(2026, 7, 8, 9), calendar: cal)
        KarmaEngine.reconcileStreaks(state: &s, now: day(2026, 7, 8, 9), calendar: cal)

        #expect(s.currentDailyStreak == 0)
    }

    @Test func onAndOffOnTheSameDayGivesNoSecondBonus() {
        var s = KarmaState()
        complete(&s, on: day(2026, 7, 1, 9))
        let points = s.points

        KarmaEngine.setVacationMode(true, state: &s, now: day(2026, 7, 1, 10), calendar: cal)
        KarmaEngine.setVacationMode(false, state: &s, now: day(2026, 7, 1, 11), calendar: cal)
        complete(&s, on: day(2026, 7, 1, 12))

        #expect(s.currentDailyStreak == 1)
        #expect(s.points == points + KarmaEngine.completionPoints)
    }

    @Test func storeSavedBeforeThisFieldStillLoads() throws {
        let old = #"{"points":5,"dailyGoal":5,"weeklyGoal":25,"vacationMode":true,"karmaEnabled":true,"currentDailyStreak":1,"maxDailyStreak":1,"currentWeeklyStreak":0,"maxWeeklyStreak":0}"#
        var s = try JSONDecoder().decode(KarmaState.self, from: Data(old.utf8))
        #expect(s.vacationStartDay == nil)

        KarmaEngine.setVacationMode(false, state: &s, now: day(2026, 7, 1), calendar: cal)
        #expect(!s.vacationMode)
    }
}
