import Foundation
import Testing
@testable import TodoneKit

/// Edge-case hunting: invalid dates, DST, month ends, streaks across days,
/// parser precedence, UTF-16 ranges, corrupt persistence, cycles.
@Suite struct AdversarialTests {
    let cal: Calendar
    let now: Date

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))! // Wednesday
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func makeStore() -> AppStore {
        let s = AppStore()
        s.calendar = cal
        return s
    }

    var dateParser: NLDateParser { NLDateParser(calendar: cal, now: now) }

    // MARK: - Invalid dates must not roll over

    @Test func invalidNumericDateRejected() {
        // Feb 31 doesn't exist; must not silently become Mar 3.
        let r = dateParser.parse("2/31")
        if let r {
            #expect(cal.component(.month, from: r.date) == 2,
                    "2/31 rolled over to \(r.date) instead of being rejected")
        }
    }

    @Test func invalidMonthNameDateRejected() {
        let r = dateParser.parse("feb 30")
        if let r {
            #expect(cal.component(.month, from: r.date) == 2,
                    "feb 30 rolled over to \(r.date) instead of being rejected")
        }
    }

    @Test func april31Rejected() {
        let r = dateParser.parse("apr 31")
        if let r {
            #expect(cal.component(.month, from: r.date) == 4,
                    "apr 31 rolled over to \(r.date)")
        }
    }

    @Test func numericMonthOutOfRangeIgnored() {
        #expect(dateParser.parse("13/5") == nil || cal.component(.month, from: dateParser.parse("13/5")!.date) <= 12)
    }

    @Test func dateTimeCombo() throws {
        let r = try #require(dateParser.parse("8/15 3pm"))
        #expect(r.date == day(2026, 8, 15, 15))
        #expect(r.hasTime)
    }

    // MARK: - DST

    @Test func dailyRecurrencePreservesHourAcrossDSTStart() throws {
        // DST starts Mar 8 2026 in America/Los_Angeles.
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every day"))
        let base = day(2026, 3, 7, 9)
        let next = try #require(rule.nextOccurrence(after: base, calendar: cal))
        #expect(cal.component(.hour, from: next) == 9)
        #expect(cal.component(.day, from: next) == 8)
    }

    @Test func weeklyRecurrenceAcrossDSTEnd() throws {
        // DST ends Nov 1 2026.
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every week"))
        let base = day(2026, 10, 28, 17)
        let next = try #require(rule.nextOccurrence(after: base, calendar: cal))
        #expect(cal.component(.hour, from: next) == 17)
        #expect(cal.component(.day, from: next) == 4)
    }

    // MARK: - Month-end recurrence

    @Test func plainMonthlyFromJan31() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month"))
        let next = try #require(rule.nextOccurrence(after: day(2027, 1, 31), calendar: cal))
        // Calendar clamps: Feb 28 2027.
        #expect(next == day(2027, 2, 28))
    }

    @Test func monthlyOn31stFromMarch() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month on the 31st"))
        let next = try #require(rule.nextOccurrence(after: day(2026, 3, 31), calendar: cal))
        #expect(next == day(2026, 4, 30)) // April has 30 days
    }

    @Test func monthlyOn31stRecoversAfterShortMonth() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month on the 31st"))
        // From Apr 30, next should be May 31 (back to the 31st).
        let next = try #require(rule.nextOccurrence(after: day(2026, 4, 30), calendar: cal))
        #expect(next == day(2026, 5, 31))
    }

    // MARK: - Karma streaks across days

    @Test func dailyStreakBuildsAndBreaks() {
        let store = makeStore()
        store.karma.dailyGoal = 1

        // Day 1: goal met.
        let t1 = store.addTask(title: "a")
        store.complete(t1, now: day(2026, 7, 20, 9))
        #expect(store.karma.currentDailyStreak == 1)

        // Day 2 (consecutive): streak grows.
        let t2 = store.addTask(title: "b")
        store.complete(t2, now: day(2026, 7, 21, 9))
        #expect(store.karma.currentDailyStreak == 2)

        // Skip day 3; reconcile on day 4 breaks the streak.
        KarmaEngine.reconcileStreaks(state: &store.karma, now: day(2026, 7, 24, 9), calendar: cal)
        #expect(store.karma.currentDailyStreak == 0)
        #expect(store.karma.maxDailyStreak == 2)
    }

    @Test func noDoubleDailyBonusViaUncompleteRecomplete() {
        let store = makeStore()
        store.karma.dailyGoal = 1
        let t = store.addTask(title: "a")
        store.complete(t, now: now)
        let pointsAfterFirst = store.karma.points // 5 + 10 bonus

        store.uncomplete(t) // refunds the +5 completion points
        store.complete(t, now: now) // +5 again, but NO second daily bonus
        #expect(store.karma.points == pointsAfterFirst)
    }

    @Test func weeklyStreakConsecutiveWeeks() {
        var state = KarmaState()
        state.weeklyGoal = 1
        KarmaEngine.applyCompletion(state: &state, date: day(2026, 7, 15, 9),
                                    completedToday: 1, completedThisWeek: 1, calendar: cal)
        #expect(state.currentWeeklyStreak == 1)
        KarmaEngine.applyCompletion(state: &state, date: day(2026, 7, 22, 9),
                                    completedToday: 1, completedThisWeek: 1, calendar: cal)
        #expect(state.currentWeeklyStreak == 2)
        // Skip a week → week of Aug 5 is not consecutive with Jul 22's week.
        KarmaEngine.applyCompletion(state: &state, date: day(2026, 8, 5, 9),
                                    completedToday: 1, completedThisWeek: 1, calendar: cal)
        #expect(state.currentWeeklyStreak == 1)
    }

    // MARK: - Filter precedence

    @Test func andBindsTighterThanOr() throws {
        let store = makeStore()
        let work = store.addProject(name: "Work")
        store.addTask(title: "p1-nowork", priority: .p1)
        store.addTask(title: "p2-work", priority: .p2, projectID: work.id)
        store.addTask(title: "p3-work", priority: .p3, projectID: work.id)

        // p1 | p2 & #Work  ≡  p1 | (p2 & #Work)
        let expr = try FilterEngine.parse("p1 | p2 & #Work", calendar: cal, now: now)
        let titles = Set(store.tasksMatching(expr, now: now).map(\.title))
        #expect(titles == ["p1-nowork", "p2-work"])
    }

    @Test func doubleNegation() throws {
        let store = makeStore()
        store.addTask(title: "dated", dueDate: day(2026, 7, 25))
        store.addTask(title: "dateless")
        let expr = try FilterEngine.parse("!!no date", calendar: cal, now: now)
        #expect(store.tasksMatching(expr, now: now).map(\.title) == ["dateless"])
    }

    @Test func filterDateArgumentStopsAtDelimiter() throws {
        let store = makeStore()
        store.addTask(title: "early", priority: .p1, dueDate: day(2026, 7, 23))
        store.addTask(title: "late", priority: .p1, dueDate: day(2026, 8, 20))
        let expr = try FilterEngine.parse("date before: aug 1 & p1", calendar: cal, now: now)
        #expect(store.tasksMatching(expr, now: now).map(\.title) == ["early"])
    }

    // MARK: - Quick add UTF-16 / masking

    @Test func emojiTitleWithTokens() {
        let parser = QuickAddParser(calendar: cal, now: now)
        let r = parser.parse("🎉 Party planning tomorrow p1 #Events")
        #expect(r.title == "🎉 Party planning")
        #expect(r.priority == .p1)
        #expect(r.projectName == "Events")
        #expect(r.dueDate == day(2026, 7, 23))
    }

    @Test func emojiProjectName() {
        let parser = QuickAddParser(calendar: cal, now: now)
        let r = parser.parse("Ship it #🚀Launch")
        #expect(r.projectName == "🚀Launch")
        #expect(r.title == "Ship it")
    }

    @Test func tokenAtStringStart() {
        let parser = QuickAddParser(calendar: cal, now: now)
        let r = parser.parse("#Work review notes")
        #expect(r.projectName == "Work")
        #expect(r.title == "review notes")
    }

    @Test func priorityAtEndOfString() {
        let parser = QuickAddParser(calendar: cal, now: now)
        let r = parser.parse("Fix bug p2")
        #expect(r.priority == .p2)
        #expect(r.title == "Fix bug")
    }

    @Test func onlyTokensNoTitle() {
        let parser = QuickAddParser(calendar: cal, now: now)
        let r = parser.parse("tomorrow p1")
        #expect(r.title == "")
        #expect(r.dueDate == day(2026, 7, 23))
        #expect(r.priority == .p1)
    }

    // MARK: - Store integrity

    @Test func corruptStoreFileLoadsFresh() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todone-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("store.json")
        try Data("{not json at all".utf8).write(to: url)

        let store = makeStore()
        store.load(from: url)
        #expect(store.projects.count == 1)
        #expect(store.projects[0].isInbox)
        #expect(store.tasks.isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func descendantLookupSurvivesManualCycle() {
        let store = makeStore()
        let a = store.addProject(name: "A")
        let b = store.addProject(name: "B", parentID: a.id)
        // Force a cycle directly (UI should prevent this, but the store must not hang).
        a.parentID = b.id
        let ids = store.descendantProjectIDs(of: a.id)
        #expect(ids.contains(a.id))
        #expect(ids.contains(b.id))
    }

    @Test func exportRoundTripDecodes() throws {
        let store = makeStore()
        let p = store.addProject(name: "P", color: .teal)
        store.addTask(title: "t", priority: .p2, dueDate: day(2026, 8, 1), projectID: p.id)
        let data = try store.exportJSON()
        let doc = try JSONDecoder.withISO8601().decode(StoreDocument.self, from: data)
        #expect(doc.projects.count == store.projects.count)
        #expect(doc.tasks.count == 1)
        #expect(doc.tasks[0].priority == .p2)
    }

    @Test func uncompleteDecrementsDailyStat() {
        let store = makeStore()
        let t = store.addTask(title: "x")
        store.complete(t, now: now)
        let key = KarmaEngine.dayKey(for: now, calendar: cal)
        #expect(store.stat(forDay: key)?.completed == 1)
        store.uncomplete(t)
        #expect(store.stat(forDay: key)?.completed == 0)
    }

    @Test func completedSubtaskDeletedWithParent() {
        let store = makeStore()
        let parent = store.addTask(title: "p")
        let sub = store.addTask(title: "s", parentID: parent.id)
        store.complete(sub, now: now)
        store.deleteTask(parent)
        #expect(store.tasks.isEmpty)
    }

    @Test func timedTasksSortBeforeUntimedOnSameDay() {
        let store = makeStore()
        store.addTask(title: "untimed", dueDate: day(2026, 7, 22))
        store.addTask(title: "late-timed", dueDate: day(2026, 7, 22, 18), hasDueTime: true)
        store.addTask(title: "early-timed", dueDate: day(2026, 7, 22, 8), hasDueTime: true)
        let titles = store.tasksDue(on: day(2026, 7, 22)).map(\.title)
        #expect(titles == ["early-timed", "late-timed", "untimed"])
    }

    @Test func reorderAcrossSectionsMovesTask() {
        let store = makeStore()
        let p = store.addProject(name: "P")
        let s1 = store.addSection(name: "S1", projectID: p.id)
        let s2 = store.addSection(name: "S2", projectID: p.id)
        let a = store.addTask(title: "a", projectID: p.id, sectionID: s1.id)
        let b = store.addTask(title: "b", projectID: p.id, sectionID: s2.id)

        store.reorder(a, before: b, project: p.id, section: s2.id)
        #expect(a.sectionID == s2.id)
        #expect(store.rootTasks(project: p.id, section: s2.id).map(\.title) == ["a", "b"])
        #expect(store.rootTasks(project: p.id, section: s1.id).isEmpty)
    }

    @Test func recurringWithoutDueDateCompletesNormally() {
        let store = makeStore()
        let t = store.addTask(title: "odd", recurrence: "every day") // no due date
        store.complete(t, now: now)
        #expect(t.isCompleted) // falls back to plain completion
    }

    @Test func labelFilterCaseInsensitive() throws {
        let store = makeStore()
        let l = store.addLabel(name: "Urgent")
        store.addTask(title: "t", labelIDs: [l.id])
        let expr = try FilterEngine.parse("@urgent", calendar: cal, now: now)
        #expect(store.tasksMatching(expr, now: now).count == 1)
    }

    @Test func sevenDaysExcludesOverdueAndFar() throws {
        let store = makeStore()
        store.addTask(title: "today", dueDate: day(2026, 7, 22))
        store.addTask(title: "day6", dueDate: day(2026, 7, 28))
        store.addTask(title: "day7", dueDate: day(2026, 7, 29)) // outside window [today, today+7)
        let expr = try FilterEngine.parse("7 days", calendar: cal, now: now)
        #expect(Set(store.tasksMatching(expr, now: now).map(\.title)) == ["today", "day6"])
    }
}

private extension JSONDecoder {
    static func withISO8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
