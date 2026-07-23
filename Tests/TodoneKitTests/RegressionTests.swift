import Foundation
import Testing
@testable import TodoneKit

/// Regressions for bugs found in the review pass.
@Suite struct RegressionTests {
    let cal: Calendar
    let now: Date

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))! // Wednesday
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func makeStore() -> AppStore {
        let s = AppStore()
        s.calendar = cal
        return s
    }

    // MARK: Unicode lowercasing (İ changes UTF-16 length when lowercased)

    @Test func turkishCapitalIDoesNotCrashOrCorruptRanges() {
        let parser = QuickAddParser(calendar: cal, now: now)
        let r = parser.parse("İstanbul trip tomorrow")
        #expect(r.title == "İstanbul trip")
        #expect(r.dueDate == day(2026, 7, 23))
    }

    @Test func uppercaseTokensStillParse() {
        let parser = QuickAddParser(calendar: cal, now: now)
        let r = parser.parse("Report TOMORROW 3PM P1 #Work EVERY WEEK")
        #expect(r.dueDate != nil)
        #expect(r.hasDueTime)
        #expect(r.priority == .p1)
        #expect(r.recurrence?.unit == .week)
    }

    // MARK: False-positive date matches

    @Test func satAsVerbIsNotADate() {
        let parser = NLDateParser(calendar: cal, now: now)
        #expect(parser.parse("we sat down and talked") == nil)
    }

    @Test func sunAsNounIsNotADate() {
        let parser = NLDateParser(calendar: cal, now: now)
        #expect(parser.parse("catch some sun") == nil)
    }

    @Test func fullSaturdayStillParses() throws {
        let parser = NLDateParser(calendar: cal, now: now)
        let r = try #require(parser.parse("brunch saturday"))
        #expect(r.date == day(2026, 7, 25))
    }

    @Test func nextSatStillParses() throws {
        let parser = NLDateParser(calendar: cal, now: now)
        let r = try #require(parser.parse("next sat"))
        #expect(r.date == day(2026, 7, 25))
    }

    @Test func streetAddressIsNotATime() {
        let parser = NLDateParser(calendar: cal, now: now)
        let r = parser.parse("meet at 15 Main St")
        #expect(r == nil || r?.hasTime == false)
    }

    // MARK: Karma integrity

    @Test func completeUncompleteCycleCannotFarmPoints() {
        let store = makeStore()
        store.karma.dailyGoal = 100 // keep goal bonuses out of the picture
        let t = store.addTask(title: "x")
        for _ in 0..<5 {
            store.complete(t, now: now)
            store.uncomplete(t)
        }
        #expect(store.karma.points == 0)
    }

    @Test func doubleCompleteCountsOnce() {
        let store = makeStore()
        let t = store.addTask(title: "x")
        store.complete(t, now: now)
        store.complete(t, now: now) // double-tap
        #expect(store.karma.points == KarmaEngine.completionPoints)
        let key = KarmaEngine.dayKey(for: now, calendar: cal)
        #expect(store.stat(forDay: key)?.completed == 1)
    }

    // MARK: Overdue recurring catch-up

    @Test func overdueEveryThreeDaysLandsTodayOrLater() {
        let store = makeStore()
        // Due Jul 10, every 3 days → Jul 13, 16, 19, 22 — lands Jul 22 (today).
        let t = store.addTask(title: "x", dueDate: day(2026, 7, 10), recurrence: "every 3 days")
        store.complete(t, now: now)
        #expect(t.dueDate == day(2026, 7, 22))
    }

    @Test func timedOverdueRecurringSkipsPastTimeToday() {
        let store = makeStore()
        // Due 9am yesterday; now is 10am. 9am today already passed → tomorrow 9am.
        let t = store.addTask(title: "x", dueDate: day(2026, 7, 21, 9),
                              hasDueTime: true, recurrence: "every day")
        store.complete(t, now: now)
        #expect(t.dueDate == day(2026, 7, 23, 9))
    }

    @Test func futureRecurringAdvancesOneStep() {
        let store = makeStore()
        let t = store.addTask(title: "x", dueDate: day(2026, 7, 25), recurrence: "every week")
        store.complete(t, now: now)
        #expect(t.dueDate == day(2026, 8, 1)) // no catch-up loop for future dates
    }

    // MARK: Month-end drift

    @Test func plainMonthlyKeepsEndOfMonthAnchor() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month"))
        // Jan 31 → Feb 28 → Mar 31 (not Mar 28).
        let feb = try #require(rule.nextOccurrence(after: day(2027, 1, 31), calendar: cal))
        #expect(feb == day(2027, 2, 28))
        let mar = try #require(rule.nextOccurrence(after: feb, calendar: cal))
        #expect(mar == day(2027, 3, 31))
    }

    @Test func plainMonthlyMidMonthUnaffected() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month"))
        let next = try #require(rule.nextOccurrence(after: day(2026, 7, 15), calendar: cal))
        #expect(next == day(2026, 8, 15))
    }

    // MARK: Corrupt store handling

    @Test func corruptStoreIsBackedUpNotDiscarded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todone-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("todone.json")
        try Data("{broken".utf8).write(to: url)

        let store = makeStore()
        store.load(from: url)
        #expect(store.lastSaveError != nil)

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("corrupt") }
        #expect(!backups.isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Date precision across save/load

    @Test func subSecondCompletionOrderSurvivesRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todone-precision-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("store.json")

        let store = makeStore()
        store.load(from: url)
        let a = store.addTask(title: "first")
        let b = store.addTask(title: "second")
        a.completedAt = now.addingTimeInterval(0.100)
        b.completedAt = now.addingTimeInterval(0.500)
        store.saveNow()

        let reload = AppStore()
        reload.calendar = cal
        reload.load(from: url)
        let ra = try #require(reload.task(a.id))
        let rb = try #require(reload.task(b.id))
        #expect(ra.completedAt! < rb.completedAt!)

        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Move appends to end

    @Test func moveAppendsToEndOfNewProject() {
        let store = makeStore()
        let p1 = store.addProject(name: "One")
        let p2 = store.addProject(name: "Two")
        store.addTask(title: "a", projectID: p2.id)
        store.addTask(title: "b", projectID: p2.id)
        let mover = store.addTask(title: "mover", projectID: p1.id) // sortOrder 1 in p1

        store.move(mover, toProject: p2.id, section: nil)
        #expect(store.rootTasks(project: p2.id, section: nil).map(\.title) == ["a", "b", "mover"])
    }

    // MARK: Filter keyword boundaries

    @Test func subtasksPluralIsCleanParseError() {
        #expect(throws: FilterParseError.self) {
            _ = try FilterEngine.parse("subtasks", calendar: cal, now: now)
        }
    }

    @Test func subtaskAmpersandNoSpaceStillParses() throws {
        let expr = try FilterEngine.parse("subtask&p1", calendar: cal, now: now)
        #expect(expr == .and(.term(.subtask), .term(.priority(.p1))))
    }

    // MARK: Project cycle safety in store operations

    @Test func deleteProjectWithManualCycleTerminates() {
        let store = makeStore()
        let a = store.addProject(name: "A")
        let b = store.addProject(name: "B", parentID: a.id)
        a.parentID = b.id // force corrupt state
        store.deleteProject(a) // must not recurse forever
        #expect(!store.projects.contains { $0.id == a.id })
        #expect(!store.projects.contains { $0.id == b.id })
    }

    @Test func canSetParentRejectsDescendants() {
        let store = makeStore()
        let a = store.addProject(name: "A")
        let b = store.addProject(name: "B", parentID: a.id)
        let c = store.addProject(name: "C")
        #expect(!store.canSetParent(of: a, to: a.id))
        #expect(!store.canSetParent(of: a, to: b.id))
        #expect(store.canSetParent(of: a, to: c.id))
        #expect(store.canSetParent(of: a, to: nil))
    }

    @Test func archiveProjectWithManualCycleTerminates() {
        let store = makeStore()
        let a = store.addProject(name: "A")
        let b = store.addProject(name: "B", parentID: a.id)
        a.parentID = b.id
        store.archiveProject(a)
        #expect(store.projects.filter { !$0.isInbox }.allSatisfy { $0.isArchived })
    }

    // MARK: Erase writes through immediately

    @Test func eraseAllPersistsImmediately() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todone-erase-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("store.json")

        let store = makeStore()
        store.load(from: url)
        store.addTask(title: "secret")
        store.saveNow()
        store.eraseAll()
        // No saveNow() call here — eraseAll itself must have written through.

        let reload = AppStore()
        reload.calendar = cal
        reload.load(from: url)
        #expect(reload.tasks.isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }
}
