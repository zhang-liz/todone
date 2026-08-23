import Foundation
import Testing
@testable import TodoneKit

@Suite struct TaskSorterTests {
    let cal: Calendar
    let now: Date
    let store: AppStore
    let project: Project

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!
        store = AppStore()
        store.calendar = cal
        project = store.addProject(name: "Work")
    }

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: Sorting

    @Test func manualKeepsDragOrder() {
        let a = store.addTask(title: "b", projectID: project.id)
        let b = store.addTask(title: "a", projectID: project.id)
        let sorted = TaskSorter.sorted([b, a], by: .manual)
        #expect(sorted.map(\.title) == ["b", "a"])
    }

    @Test func dueDateSortsUndatedLast() {
        let late = store.addTask(title: "late", dueDate: day(2026, 8, 1), projectID: project.id)
        let none = store.addTask(title: "none", projectID: project.id)
        let soon = store.addTask(title: "soon", dueDate: day(2026, 7, 23), projectID: project.id)

        let sorted = TaskSorter.sorted([late, none, soon], by: .dueDate)
        #expect(sorted.map(\.title) == ["soon", "late", "none"])
    }

    @Test func prioritySortsP1First() {
        let low = store.addTask(title: "low", priority: .p4, projectID: project.id)
        let high = store.addTask(title: "high", priority: .p1, projectID: project.id)
        let mid = store.addTask(title: "mid", priority: .p2, projectID: project.id)

        let sorted = TaskSorter.sorted([low, high, mid], by: .priority)
        #expect(sorted.map(\.title) == ["high", "mid", "low"])
    }

    @Test func alphabeticalIsCaseInsensitive() {
        let a = store.addTask(title: "banana", projectID: project.id)
        let b = store.addTask(title: "Apple", projectID: project.id)

        let sorted = TaskSorter.sorted([a, b], by: .alphabetical)
        #expect(sorted.map(\.title) == ["Apple", "banana"])
    }

    // Equal keys must not shuffle between renders.
    @Test func tiesFallBackToManualOrder() {
        let first = store.addTask(title: "same", priority: .p1, projectID: project.id)
        let second = store.addTask(title: "same", priority: .p1, projectID: project.id)

        let sorted = TaskSorter.sorted([second, first], by: .priority)
        #expect(sorted.map(\.id) == [first.id, second.id])
    }

    // MARK: Grouping

    @Test func noGroupingReturnsOneUntitledRun() {
        let t = store.addTask(title: "x", projectID: project.id)
        let groups = TaskSorter.grouped([t], by: .none, calendar: cal, now: now)
        #expect(groups.count == 1)
        #expect(groups[0].title.isEmpty)
        #expect(groups[0].tasks.map(\.title) == ["x"])
    }

    @Test func groupingByPrioritySkipsEmptyLevels() {
        let p1 = store.addTask(title: "urgent", priority: .p1, projectID: project.id)
        let p3 = store.addTask(title: "later", priority: .p3, projectID: project.id)

        let groups = TaskSorter.grouped([p1, p3], by: .priority, calendar: cal, now: now)
        #expect(groups.map(\.title) == ["P1", "P3"])
    }

    @Test func groupingByDueDateSplitsOverdueTodayUpcomingUndated() {
        let overdue = store.addTask(title: "overdue", dueDate: day(2026, 7, 20), projectID: project.id)
        let today = store.addTask(title: "today", dueDate: day(2026, 7, 22), projectID: project.id)
        let later = store.addTask(title: "later", dueDate: day(2026, 7, 30), projectID: project.id)
        let undated = store.addTask(title: "undated", projectID: project.id)

        let groups = TaskSorter.grouped([overdue, today, later, undated],
                                        by: .dueDate, calendar: cal, now: now)
        #expect(groups.map(\.title) == ["Overdue", "Today", "Upcoming", "No Date"])
        #expect(groups[0].tasks.map(\.title) == ["overdue"])
        #expect(groups[3].tasks.map(\.title) == ["undated"])
    }

    @Test func groupingByProjectUsesFirstAppearanceOrder() {
        let other = store.addProject(name: "Home")
        let a = store.addTask(title: "in work", projectID: project.id)
        let b = store.addTask(title: "in home", projectID: other.id)

        let groups = TaskSorter.grouped([a, b], by: .project, calendar: cal, now: now,
                                        projectName: { store.project($0)?.name })
        #expect(groups.map(\.title) == ["Work", "Home"])
    }

    @Test func emptyInputProducesNoGroups() {
        #expect(TaskSorter.grouped([], by: .priority, calendar: cal, now: now).isEmpty)
        #expect(TaskSorter.grouped([], by: .dueDate, calendar: cal, now: now).isEmpty)
    }

    // MARK: Store wiring

    @Test func rootTasksHonoursTheProjectSort() {
        store.addTask(title: "b", priority: .p4, projectID: project.id)
        store.addTask(title: "a", priority: .p1, projectID: project.id)

        #expect(store.rootTasks(project: project.id, section: nil).map(\.title) == ["b", "a"])

        project.taskSort = .priority
        #expect(store.rootTasks(project: project.id, section: nil).map(\.title) == ["a", "b"])
    }

    @Test func sortAndGroupingSurviveASaveLoadRoundTrip() throws {
        project.taskSort = .dueDate
        project.grouping = .priority

        let data = try AppStore.encoder.encode(store.document())
        let doc = try AppStore.decoder.decode(StoreDocument.self, from: data)
        let restored = try #require(doc.projects.first { $0.name == "Work" })
        #expect(restored.taskSort == .dueDate)
        #expect(restored.grouping == .priority)
    }

    @Test func projectSavedBeforeTheseFieldsDefaultsToManual() throws {
        let json = """
        {"id":"3D9F1E64-0E2B-4C46-9F5E-9C0B1B7A4E33","name":"Old","color":"charcoal",
         "isFavorite":false,"isInbox":false,"viewStyle":"list","sortOrder":1,"isArchived":false}
        """
        let p = try AppStore.decoder.decode(Project.self, from: Data(json.utf8))
        #expect(p.taskSort == .manual)
        #expect(p.grouping == .none)
    }
}
