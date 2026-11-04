import Testing
@testable import TodoneKit

@Suite struct MoveTaskTests {
    // The subtask kept its parent link, so the target project never listed it.
    @Test func subtaskMovedToAnotherProjectBecomesARootTask() {
        let s = AppStore()
        let a = s.addProject(name: "A")
        let b = s.addProject(name: "B")
        let parent = s.addTask(title: "parent", projectID: a.id)
        let sub = s.addTask(title: "sub", projectID: a.id, parentID: parent.id)

        s.move(sub, toProject: b.id, section: nil)

        #expect(sub.parentID == nil)
        #expect(s.rootTasks(project: b.id, section: nil).map(\.title) == ["sub"])

        // Deleting the old project must not take the moved task with it.
        s.deleteProject(a)
        #expect(s.task(sub.id) != nil)
    }

    @Test func movingAParentKeepsItsSubtasksAttached() {
        let s = AppStore()
        let a = s.addProject(name: "A")
        let b = s.addProject(name: "B")
        let parent = s.addTask(title: "parent", projectID: a.id)
        let sub = s.addTask(title: "sub", projectID: a.id, parentID: parent.id)

        s.move(parent, toProject: b.id, section: nil)

        #expect(sub.parentID == parent.id)
        #expect(sub.projectID == b.id)
    }

    @Test func subtaskMovedWithinItsProjectKeepsItsParent() {
        let s = AppStore()
        let a = s.addProject(name: "A")
        let parent = s.addTask(title: "parent", projectID: a.id)
        let sub = s.addTask(title: "sub", projectID: a.id, parentID: parent.id)

        s.move(sub, toProject: a.id, section: nil)

        #expect(sub.parentID == parent.id)
    }
}
