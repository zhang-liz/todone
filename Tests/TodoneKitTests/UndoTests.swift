import Foundation
import Testing
@testable import TodoneKit

/// Undo restores a snapshot of the whole store, so these cover both the
/// mechanism (stack depth, redo invalidation, deep copying) and a
/// representative action from each family of mutations.
@Suite struct UndoTests {
    let cal: Calendar
    let now: Date

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        cal = c
        now = c.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!
    }

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func makeStore() -> AppStore {
        let s = AppStore()
        s.calendar = cal
        return s
    }

    // MARK: Mechanism

    @Test func nothingToUndoOnAFreshStore() {
        let s = makeStore()
        #expect(!s.canUndo)
        #expect(!s.canRedo)
        s.undo()  // must not crash or corrupt
        #expect(s.tasks.isEmpty)
    }

    @Test func undoThenRedoRoundTrips() {
        let s = makeStore()
        s.addTask(title: "a")
        #expect(s.canUndo)

        s.undo()
        #expect(s.tasks.isEmpty)
        #expect(s.canRedo)

        s.redo()
        #expect(s.tasks.map(\.title) == ["a"])
    }

    @Test func newEditClearsTheRedoStack() {
        let s = makeStore()
        s.addTask(title: "a")
        s.undo()
        #expect(s.canRedo)

        s.addTask(title: "b")
        #expect(!s.canRedo)
        #expect(s.tasks.map(\.title) == ["b"])
    }

    @Test func undoStackIsBounded() {
        let s = makeStore()
        for i in 0..<(AppStore.undoLimit + 20) {
            s.addTask(title: "t\(i)")
        }
        var steps = 0
        while s.canUndo {
            s.undo()
            steps += 1
            if steps > AppStore.undoLimit + 50 { break }  // guard against a runaway loop
        }
        #expect(steps == AppStore.undoLimit)
    }

    // A snapshot that shared object references with the live store would
    // "restore" values that had already been mutated in place.
    @Test func undoRestoresMutatedFieldsNotJustCollections() {
        let s = makeStore()
        let t = s.addTask(title: "original", priority: .p4)

        s.updateTask(t) { $0.title = "edited"; $0.priority = .p1 }
        #expect(s.tasks[0].title == "edited")

        s.undo()
        #expect(s.tasks[0].title == "original")
        #expect(s.tasks[0].priority == .p4)
    }

    @Test func undoAfterUndoWalksFurtherBack() {
        let s = makeStore()
        s.addTask(title: "first")
        s.addTask(title: "second")

        s.undo()
        #expect(s.tasks.map(\.title) == ["first"])
        s.undo()
        #expect(s.tasks.isEmpty)
    }

    // MARK: Representative actions

    @Test func undoRestoresADeletedTaskAndItsSubtasks() {
        let s = makeStore()
        let parent = s.addTask(title: "parent")
        s.addTask(title: "child", parentID: parent.id)
        #expect(s.tasks.count == 2)

        s.deleteTask(parent)
        #expect(s.tasks.isEmpty)

        s.undo()
        #expect(Set(s.tasks.map(\.title)) == ["parent", "child"])
    }

    @Test func undoRevertsCompletionIncludingKarma() {
        let s = makeStore()
        let t = s.addTask(title: "x")
        let pointsBefore = s.karma.points

        s.complete(t, now: now)
        #expect(s.tasks[0].isCompleted)
        #expect(s.karma.points > pointsBefore)

        s.undo()
        #expect(!s.tasks[0].isCompleted)
        #expect(s.karma.points == pointsBefore)
    }

    @Test func undoRevertsRecurringAdvance() {
        let s = makeStore()
        let t = s.addTask(title: "water", dueDate: day(2026, 7, 22), recurrence: "every 3 days")

        s.complete(t, now: now)
        #expect(s.tasks[0].dueDate == day(2026, 7, 25))

        s.undo()
        #expect(s.tasks[0].dueDate == day(2026, 7, 22))
    }

    @Test func undoRevertsAProjectArchive() {
        let s = makeStore()
        let p = s.addProject(name: "Work")

        s.archiveProject(p)
        #expect(s.archivedProjects.map(\.name) == ["Work"])

        s.undo()
        #expect(s.archivedProjects.isEmpty)
        #expect(s.childProjects(of: nil).map(\.name) == ["Work"])
    }

    @Test func undoRevertsAProjectDeleteWithItsTasks() {
        let s = makeStore()
        let p = s.addProject(name: "Doomed")
        s.addTask(title: "inside", projectID: p.id)

        s.deleteProject(p)
        #expect(s.tasks.isEmpty)

        s.undo()
        #expect(s.childProjects(of: nil).map(\.name) == ["Doomed"])
        #expect(s.tasks.map(\.title) == ["inside"])
    }

    @Test func undoRevertsAMove() {
        let s = makeStore()
        let a = s.addProject(name: "A")
        let b = s.addProject(name: "B")
        let t = s.addTask(title: "x", projectID: a.id)

        s.move(t, toProject: b.id, section: nil)
        #expect(s.tasks[0].projectID == b.id)

        s.undo()
        #expect(s.tasks[0].projectID == a.id)
    }

    @Test func undoRevertsLabelAndFilterChanges() {
        let s = makeStore()
        let label = s.addLabel(name: "urgent")
        s.deleteLabel(label)
        #expect(s.labels.isEmpty)
        s.undo()
        #expect(s.labels.map(\.name) == ["urgent"])

        s.addFilter(name: "P1", query: "p1")
        #expect(s.filters.map(\.name) == ["P1"])
        s.undo()
        #expect(s.filters.isEmpty)
    }

    // MARK: Bulk actions

    @Test func aBulkActionIsOneUndoStep() {
        let s = makeStore()
        let a = s.addTask(title: "a")
        let b = s.addTask(title: "b")
        let c = s.addTask(title: "c")

        s.asSingleUndoStep {
            for t in [a, b, c] { s.complete(t, now: now) }
        }
        #expect(s.tasks.filter { !$0.isCompleted }.isEmpty)

        s.undo()
        #expect(s.tasks.filter { $0.isCompleted }.isEmpty)
    }

    @Test func nestedGroupingStillCollapsesToOneStep() {
        let s = makeStore()
        let a = s.addTask(title: "a")
        let b = s.addTask(title: "b")

        s.asSingleUndoStep {
            s.asSingleUndoStep {
                for t in [a, b] { s.deleteTask(t) }
            }
        }
        #expect(s.tasks.isEmpty)

        s.undo()
        #expect(Set(s.tasks.map(\.title)) == ["a", "b"])
    }

    // MARK: Erase is deliberately not undoable

    @Test func eraseAllClearsUndoHistory() {
        let s = makeStore()
        s.addTask(title: "a")
        #expect(s.canUndo)

        s.eraseAll()
        #expect(!s.canUndo)
        #expect(!s.canRedo)
        #expect(s.tasks.isEmpty)
    }

    // MARK: Persistence

    @Test func undoPersistsToDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todone-undo-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("store.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let s = makeStore()
        s.load(from: url)
        s.addTask(title: "keep")
        s.addTask(title: "oops")
        s.undo()
        s.saveNow()

        let reloaded = makeStore()
        reloaded.load(from: url)
        #expect(reloaded.tasks.map(\.title) == ["keep"])
    }
}
