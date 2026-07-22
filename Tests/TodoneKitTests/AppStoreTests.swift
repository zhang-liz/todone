import Foundation
import Testing
@testable import TodoneKit

@Suite struct AppStoreTests {
    let cal: Calendar
    let now: Date

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!
    }

    func makeStore() -> AppStore {
        let s = AppStore()
        s.calendar = cal
        return s
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func inboxIsCreatedOnce() {
        let store = makeStore()
        let a = store.inbox
        let b = store.ensureInbox()
        #expect(a.id == b.id)
        #expect(store.projects.filter(\.isInbox).count == 1)
    }

    @Test func addTaskDefaultsToInbox() {
        let store = makeStore()
        let t = store.addTask(title: "hello")
        #expect(t.projectID == store.inbox.id)
        #expect(store.events.last?.type == .added)
    }

    @Test func completeSimpleTask() {
        let store = makeStore()
        let t = store.addTask(title: "x")
        store.complete(t, now: now)
        #expect(t.isCompleted)
        #expect(store.karma.points == KarmaEngine.completionPoints)
        #expect(store.events.last?.type == .completed)
    }

    @Test func completeRecurringAdvancesInsteadOfCompleting() {
        let store = makeStore()
        let t = store.addTask(title: "habit", dueDate: day(2026, 7, 22, 9),
                              hasDueTime: true, recurrence: "every day")
        store.complete(t, now: now)
        #expect(!t.isCompleted)
        #expect(t.dueDate == day(2026, 7, 23, 9))
        // Karma still counts it.
        #expect(store.karma.points == KarmaEngine.completionPoints)
    }

    @Test func strictRecurrenceAdvancesFromCompletionDate() {
        let store = makeStore()
        // Due Jul 10 9am, completed late on Jul 22 → next is Jul 23 (day after completion), 9am kept.
        let t = store.addTask(title: "strict", dueDate: day(2026, 7, 10, 9),
                              hasDueTime: true, recurrence: "every! day")
        store.complete(t, now: now)
        #expect(t.dueDate == day(2026, 7, 23, 9))
    }

    @Test func plainRecurrenceAdvancesFromDueDate() {
        let store = makeStore()
        // Due Jul 10, completed Jul 22 → next is Jul 11 (from due date).
        let t = store.addTask(title: "loose", dueDate: day(2026, 7, 10),
                              recurrence: "every day")
        store.complete(t, now: now)
        #expect(t.dueDate == day(2026, 7, 11))
    }

    @Test func uncompleteRestores() {
        let store = makeStore()
        let t = store.addTask(title: "x")
        store.complete(t, now: now)
        store.uncomplete(t)
        #expect(!t.isCompleted)
        #expect(store.events.last?.type == .uncompleted)
    }

    @Test func deleteTaskCascadesToSubtasksAndReminders() {
        let store = makeStore()
        let parent = store.addTask(title: "parent")
        let child = store.addTask(title: "child", parentID: parent.id)
        let grandchild = store.addTask(title: "grandchild", parentID: child.id)
        store.addReminder(taskID: grandchild.id, kind: .relative(minutesBefore: 10))

        store.deleteTask(parent)
        #expect(store.tasks.isEmpty)
        #expect(store.reminders.isEmpty)
    }

    @Test func deleteProjectCascades() {
        let store = makeStore()
        let p = store.addProject(name: "P")
        let child = store.addProject(name: "C", parentID: p.id)
        let s = store.addSection(name: "S", projectID: p.id)
        store.addTask(title: "t1", projectID: p.id, sectionID: s.id)
        store.addTask(title: "t2", projectID: child.id)

        store.deleteProject(p)
        #expect(store.projects.filter { !$0.isInbox }.isEmpty)
        #expect(store.tasks.isEmpty)
        #expect(store.sections.isEmpty)
    }

    @Test func inboxCannotBeDeleted() {
        let store = makeStore()
        store.deleteProject(store.inbox)
        #expect(store.projects.contains { $0.isInbox })
    }

    @Test func deleteSectionMovesTasksToProjectBody() {
        let store = makeStore()
        let p = store.addProject(name: "P")
        let s = store.addSection(name: "S", projectID: p.id)
        let t = store.addTask(title: "t", projectID: p.id, sectionID: s.id)

        store.deleteSection(s)
        #expect(t.sectionID == nil)
        #expect(store.tasks.count == 1)
    }

    @Test func deleteLabelRemovesFromTasks() {
        let store = makeStore()
        let l = store.addLabel(name: "x")
        let t = store.addTask(title: "t", labelIDs: [l.id])
        store.deleteLabel(l)
        #expect(t.labelIDs.isEmpty)
    }

    @Test func addLabelDeduplicatesCaseInsensitively() {
        let store = makeStore()
        let a = store.addLabel(name: "Home")
        let b = store.addLabel(name: "home")
        #expect(a.id == b.id)
    }

    @Test func reorderPlacesTaskBeforeTarget() {
        let store = makeStore()
        let p = store.addProject(name: "P")
        let a = store.addTask(title: "a", projectID: p.id)
        let b = store.addTask(title: "b", projectID: p.id)
        let c = store.addTask(title: "c", projectID: p.id)

        store.reorder(c, before: a, project: p.id, section: nil)
        let titles = store.rootTasks(project: p.id, section: nil).map(\.title)
        #expect(titles == ["c", "a", "b"])
        _ = b
    }

    @Test func moveTaskMovesSubtasks() {
        let store = makeStore()
        let p1 = store.addProject(name: "One")
        let p2 = store.addProject(name: "Two")
        let parent = store.addTask(title: "parent", projectID: p1.id)
        let child = store.addTask(title: "child", projectID: p1.id, parentID: parent.id)

        store.move(parent, toProject: p2.id, section: nil)
        #expect(child.projectID == p2.id)
    }

    @Test func addFromQuickAddCreatesEntities() {
        let store = makeStore()
        let parser = QuickAddParser(calendar: cal, now: now)
        let parsed = parser.parse("Pay rent tomorrow p1 #Finance /Bills @money")
        let t = store.addTask(from: parsed)

        let project = store.project(t.projectID)
        #expect(project?.name == "Finance")
        let section = t.sectionID.flatMap { store.section($0) }
        #expect(section?.name == "Bills")
        #expect(t.labelIDs.count == 1)
        #expect(store.label(t.labelIDs[0])?.name == "money")
        #expect(t.priority == .p1)
        #expect(t.dueDate == day(2026, 7, 23))
    }

    @Test func persistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todone-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("store.json")

        let store = makeStore()
        store.load(from: url)
        let p = store.addProject(name: "Work", color: .blue)
        let s = store.addSection(name: "Sprint", projectID: p.id)
        let l = store.addLabel(name: "urgent", color: .red)
        let t = store.addTask(title: "Ship it", details: "soon", priority: .p1,
                              dueDate: day(2026, 7, 30, 15), hasDueTime: true,
                              recurrence: "every week", projectID: p.id,
                              sectionID: s.id, labelIDs: [l.id])
        store.addReminder(taskID: t.id, kind: .relative(minutesBefore: 30))
        store.addFilter(name: "Hot", query: "p1 & today", color: .red)
        store.saveNow()

        let restored = AppStore()
        restored.calendar = cal
        restored.load(from: url)

        #expect(restored.projects.count == store.projects.count)
        let rt = try #require(restored.task(t.id))
        #expect(rt.title == "Ship it")
        #expect(rt.priority == .p1)
        #expect(rt.dueDate == day(2026, 7, 30, 15))
        #expect(rt.hasDueTime)
        #expect(rt.recurrence == "every week")
        #expect(rt.sectionID == s.id)
        #expect(rt.labelIDs == [l.id])
        #expect(restored.reminders.count == 1)
        #expect(restored.filters.first?.query == "p1 & today")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func karmaDailyGoalBonusAndStreak() {
        let store = makeStore()
        store.karma.dailyGoal = 2
        for i in 0..<2 {
            let t = store.addTask(title: "t\(i)")
            store.complete(t, now: now)
        }
        // 2 completions * 5 + daily goal bonus 10.
        #expect(store.karma.points == 20)
        #expect(store.karma.currentDailyStreak == 1)

        // Third completion: just +5, no second bonus.
        let t = store.addTask(title: "extra")
        store.complete(t, now: now)
        #expect(store.karma.points == 25)
    }

    @Test func vacationModeFreezesKarma() {
        let store = makeStore()
        store.karma.vacationMode = true
        let t = store.addTask(title: "x")
        store.complete(t, now: now)
        #expect(store.karma.points == 0)
    }

    @Test func karmaLevels() {
        #expect(KarmaLevel.level(for: 0) == .beginner)
        #expect(KarmaLevel.level(for: 499) == .beginner)
        #expect(KarmaLevel.level(for: 500) == .novice)
        #expect(KarmaLevel.level(for: 50000) == .enlightened)
    }

    @Test func todayCountIncludesOverdue() {
        let store = makeStore()
        store.addTask(title: "today", dueDate: day(2026, 7, 22))
        store.addTask(title: "yesterday", dueDate: day(2026, 7, 21))
        store.addTask(title: "future", dueDate: day(2026, 8, 1))
        #expect(store.todayCount(now: now) == 2)
    }

    @Test func eraseAllResetsEverythingButKeepsInbox() {
        let store = makeStore()
        store.addTask(title: "x")
        store.addProject(name: "P")
        store.eraseAll()
        #expect(store.tasks.isEmpty)
        #expect(store.projects.count == 1)
        #expect(store.projects[0].isInbox)
    }
}
