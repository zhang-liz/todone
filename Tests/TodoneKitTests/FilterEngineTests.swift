import Foundation
import Testing
@testable import TodoneKit

@Suite struct FilterEngineTests {
    let cal: Calendar
    let now: Date
    let store: AppStore

    let work: Project
    let personal: Project
    let subProject: Project
    let urgentLabel: TaskLabel

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!
        store = AppStore()
        store.calendar = cal
        work = store.addProject(name: "Work")
        personal = store.addProject(name: "Personal")
        subProject = store.addProject(name: "Reports", parentID: work.id)
        urgentLabel = store.addLabel(name: "urgent")
    }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func matches(_ query: String) throws -> [TodoTask] {
        let expr = try FilterEngine.parse(query, calendar: cal, now: now)
        return store.tasksMatching(expr, now: now)
    }

    @Test func todayAndPriority() throws {
        store.addTask(title: "urgent today", priority: .p1, dueDate: day(2026, 7, 22), projectID: work.id)
        store.addTask(title: "chill today", priority: .p3, dueDate: day(2026, 7, 22), projectID: work.id)
        store.addTask(title: "urgent later", priority: .p1, dueDate: day(2026, 7, 30), projectID: work.id)

        let r = try matches("today & p1")
        #expect(r.map(\.title) == ["urgent today"])
    }

    @Test func orAndParens() throws {
        store.addTask(title: "a", priority: .p1, projectID: work.id)
        store.addTask(title: "b", priority: .p2, projectID: personal.id)
        store.addTask(title: "c", priority: .p3, projectID: personal.id)

        let r = try matches("(p1 | p2) & #Personal")
        #expect(r.map(\.title) == ["b"])
    }

    @Test func negation() throws {
        store.addTask(title: "has date", dueDate: day(2026, 7, 25), projectID: work.id)
        store.addTask(title: "no date", projectID: work.id)

        let r = try matches("!no date")
        #expect(r.map(\.title) == ["has date"])
    }

    @Test func overdueRespectsTime() throws {
        store.addTask(title: "late meeting", dueDate: day(2026, 7, 22, 9), hasDueTime: true, projectID: work.id)
        store.addTask(title: "today all day", dueDate: day(2026, 7, 22), projectID: work.id)
        store.addTask(title: "yesterday", dueDate: day(2026, 7, 21), projectID: work.id)

        let r = try matches("overdue")
        #expect(Set(r.map(\.title)) == ["late meeting", "yesterday"])
    }

    @Test func projectWithSubprojects() throws {
        store.addTask(title: "in work", projectID: work.id)
        store.addTask(title: "in reports", projectID: subProject.id)
        store.addTask(title: "in personal", projectID: personal.id)

        let plain = try matches("#Work")
        #expect(plain.map(\.title) == ["in work"])

        let withSub = try matches("##Work")
        #expect(Set(withSub.map(\.title)) == ["in work", "in reports"])
    }

    @Test func labelAndNoLabel() throws {
        store.addTask(title: "tagged", projectID: work.id, labelIDs: [urgentLabel.id])
        store.addTask(title: "untagged", projectID: work.id)

        #expect(try matches("@urgent").map(\.title) == ["tagged"])
        #expect(try matches("no label").map(\.title) == ["untagged"])
    }

    @Test func nextSevenDays() throws {
        store.addTask(title: "in range", dueDate: day(2026, 7, 25), projectID: work.id)
        store.addTask(title: "too far", dueDate: day(2026, 8, 15), projectID: work.id)
        store.addTask(title: "yesterday", dueDate: day(2026, 7, 21), projectID: work.id)

        let r = try matches("7 days")
        #expect(r.map(\.title) == ["in range"])
    }

    @Test func dateBeforeWithNaturalLanguage() throws {
        store.addTask(title: "soon", dueDate: day(2026, 7, 23), projectID: work.id)
        store.addTask(title: "later", dueDate: day(2026, 8, 20), projectID: work.id)

        let r = try matches("date before: aug 1")
        #expect(r.map(\.title) == ["soon"])
    }

    @Test func searchTerm() throws {
        store.addTask(title: "Send report", projectID: work.id)
        store.addTask(title: "Buy milk", details: "the report kind", projectID: work.id)
        store.addTask(title: "Other", projectID: work.id)

        let r = try matches("search: report")
        #expect(Set(r.map(\.title)) == ["Send report", "Buy milk"])
    }

    @Test func subtaskTerm() throws {
        let parent = store.addTask(title: "Parent", projectID: work.id)
        store.addTask(title: "Child", projectID: work.id, parentID: parent.id)

        #expect(try matches("subtask").map(\.title) == ["Child"])
        #expect(Set(try matches("!subtask").map(\.title)) == ["Parent"])
    }

    @Test func recurringTerm() throws {
        store.addTask(title: "Habit", dueDate: day(2026, 7, 22), recurrence: "every day", projectID: work.id)
        store.addTask(title: "Once", projectID: work.id)

        #expect(try matches("recurring").map(\.title) == ["Habit"])
    }

    @Test func completedTasksExcluded() throws {
        let t = store.addTask(title: "done", dueDate: day(2026, 7, 22), projectID: work.id)
        store.complete(t, now: now)
        store.addTask(title: "open", dueDate: day(2026, 7, 22), projectID: work.id)

        #expect(try matches("today").map(\.title) == ["open"])
    }

    @Test func invalidQueryThrows() {
        #expect(throws: FilterParseError.self) {
            _ = try FilterEngine.parse("today &", calendar: cal, now: now)
        }
        #expect(throws: FilterParseError.self) {
            _ = try FilterEngine.parse("(today", calendar: cal, now: now)
        }
        #expect(throws: FilterParseError.self) {
            _ = try FilterEngine.parse("nonsense words", calendar: cal, now: now)
        }
    }

    @Test func quotedProjectName() throws {
        let big = store.addProject(name: "Big Plans")
        store.addTask(title: "inside", projectID: big.id)

        let r = try matches("#\"Big Plans\"")
        #expect(r.map(\.title) == ["inside"])
    }

    // Names are read code unit by code unit, so an emoji — two UTF-16 units —
    // used to be sliced in half and arrive as replacement characters.
    @Test func emojiProjectName() throws {
        let party = store.addProject(name: "Welcome 👋")
        store.addTask(title: "inside", projectID: party.id)
        store.addTask(title: "outside", projectID: work.id)

        #expect(try matches("#\"Welcome 👋\"").map(\.title) == ["inside"])
    }

    @Test func emojiLabelAndSearch() throws {
        let tag = store.addLabel(name: "🎉party")
        store.addTask(title: "tagged", projectID: work.id, labelIDs: [tag.id])
        store.addTask(title: "🎉 celebrate", projectID: work.id)

        #expect(try matches("@🎉party").map(\.title) == ["tagged"])
        #expect(try matches("search: 🎉").map(\.title) == ["🎉 celebrate"])
    }
}
