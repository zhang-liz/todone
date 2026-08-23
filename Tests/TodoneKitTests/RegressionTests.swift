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

    // A monthly date that clamps to month-end is indistinguishable from a
    // deliberate month-end date when judged from the base alone, so completing
    // a task on the 30th used to migrate it to the 31st permanently.
    @Test func monthlyOn30thDoesNotDriftToMonthEnd() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month"))

        let feb = try #require(rule.nextOccurrence(after: day(2027, 1, 30), calendar: cal, anchorDay: 30))
        #expect(feb == day(2027, 2, 28))  // clamped, February is short

        let mar = try #require(rule.nextOccurrence(after: feb, calendar: cal, anchorDay: 30))
        #expect(mar == day(2027, 3, 30))  // back to the 30th, not the 31st
    }

    @Test func completingMonthlyTaskKeepsItsDayOfMonth() throws {
        let s = makeStore()
        let t = s.addTask(title: "rent", dueDate: day(2027, 1, 30), recurrence: "every month")

        s.complete(t, now: day(2027, 1, 30, 12))
        #expect(t.dueDate == day(2027, 2, 28))  // clamped into February

        s.complete(t, now: day(2027, 2, 28, 12))
        #expect(t.dueDate == day(2027, 3, 30))  // recovers the 30th; no month-end jump
        #expect(t.recurrenceAnchorDay == 30)
    }

    @Test func taskSavedWithoutAnchorDayStillDecodes() throws {
        // A task encoded before recurrenceAnchorDay existed.
        let json = """
        {"id":"1D9F1E64-0E2B-4C46-9F5E-9C0B1B7A4E11","title":"rent","details":"",
         "priority":4,"dueDate":"2027-01-30T12:00:00.000Z","hasDueTime":false,
         "recurrence":"every month","sortOrder":1,"createdAt":"2027-01-01T12:00:00.000Z",
         "projectID":"2D9F1E64-0E2B-4C46-9F5E-9C0B1B7A4E22","labelIDs":[]}
        """
        let task = try AppStore.decoder.decode(TodoTask.self, from: Data(json.utf8))
        #expect(task.recurrenceAnchorDay == nil)
        #expect(task.recurrence == "every month")
        #expect(task.title == "rent")
    }

    @Test func leapDayMonthlyDoesNotJumpToMonthEnd() throws {
        let (rule, _) = try #require(RecurrenceRule.parse(from: "every month"))
        let next = try #require(rule.nextOccurrence(after: day(2028, 2, 29), calendar: cal, anchorDay: 29))
        #expect(next == day(2028, 3, 29))
    }

    @Test func genuineMonthEndSeriesStillTracksMonthEnd() throws {
        let s = makeStore()
        let t = s.addTask(title: "invoice", dueDate: day(2027, 1, 31), recurrence: "every month")

        s.complete(t, now: day(2027, 1, 31, 12))
        #expect(t.dueDate == day(2027, 2, 28))

        s.complete(t, now: day(2027, 2, 28, 12))
        #expect(t.dueDate == day(2027, 3, 31))  // 31st anchor survives the short month
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

    // MARK: Unarchiving

    @Test func archivedProjectsAreListedSoTheyCanBeRecovered() {
        let store = makeStore()
        let keep = store.addProject(name: "Keep")
        let gone = store.addProject(name: "Gone")
        store.archiveProject(gone)

        #expect(store.childProjects(of: nil).map(\.name) == ["Keep"])
        #expect(store.archivedProjects.map(\.name) == ["Gone"])
        _ = keep
    }

    @Test func unarchiveRestoresProjectAndItsTasks() {
        let store = makeStore()
        let p = store.addProject(name: "Old")
        let t = store.addTask(title: "buried", projectID: p.id)
        store.archiveProject(p)
        #expect(store.childProjects(of: nil).isEmpty)

        store.archiveProject(p, archived: false)
        #expect(store.childProjects(of: nil).map(\.name) == ["Old"])
        #expect(store.archivedProjects.isEmpty)
        #expect(store.rootTasks(project: p.id, section: nil).map(\.title) == ["buried"])
        _ = t
    }

    @Test func unarchiveCascadesToChildren() {
        let store = makeStore()
        let parent = store.addProject(name: "Parent")
        let child = store.addProject(name: "Child", parentID: parent.id)
        store.archiveProject(parent)
        #expect(child.isArchived)

        store.archiveProject(parent, archived: false)
        #expect(!child.isArchived)
        #expect(store.childProjects(of: parent.id).map(\.name) == ["Child"])
    }

    // Restoring a child alone used to leave it inside a still-archived parent,
    // where childProjects(of: nil) never reaches it — hidden all over again.
    @Test func unarchiveChildAlsoRestoresItsAncestors() {
        let store = makeStore()
        let parent = store.addProject(name: "Parent")
        let child = store.addProject(name: "Child", parentID: parent.id)
        store.archiveProject(parent)

        store.archiveProject(child, archived: false)
        #expect(!child.isArchived)
        #expect(!parent.isArchived)
        #expect(store.childProjects(of: nil).map(\.name) == ["Parent"])
        #expect(store.childProjects(of: parent.id).map(\.name) == ["Child"])
    }

    @Test func unarchiveWithManualCycleTerminates() {
        let store = makeStore()
        let a = store.addProject(name: "A")
        let b = store.addProject(name: "B", parentID: a.id)
        store.archiveProject(a)
        a.parentID = b.id  // corrupt store: parent cycle

        store.archiveProject(b, archived: false)
        #expect(!a.isArchived)
        #expect(!b.isArchived)
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
