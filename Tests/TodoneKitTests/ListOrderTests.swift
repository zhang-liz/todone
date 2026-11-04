import Testing
@testable import TodoneKit

@Suite struct ListOrderTests {
    // Subtasks were left out, so J/K skipped them and shift-click could not reach them.
    @Test func subtasksFollowTheirParent() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let a = s.addTask(title: "a", projectID: p.id)
        let b = s.addTask(title: "b", projectID: p.id)
        let sub = s.addTask(title: "sub", projectID: p.id, parentID: a.id)
        let subsub = s.addTask(title: "subsub", projectID: p.id, parentID: sub.id)

        #expect(s.listOrder(project: p.id) == [a.id, sub.id, subsub.id, b.id])
    }

    @Test func sectionsFollowTheTasksWithoutOne() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let section = s.addSection(name: "Doing", projectID: p.id)
        let inSection = s.addTask(title: "x", projectID: p.id, sectionID: section.id)
        let loose = s.addTask(title: "y", projectID: p.id)

        #expect(s.listOrder(project: p.id) == [loose.id, inSection.id])
    }

    // With grouping on, J/K moved in stored order, not the order on screen.
    @Test func groupsSetTheOrder() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        p.grouping = .priority
        let low = s.addTask(title: "low", priority: .p4, projectID: p.id)
        let high = s.addTask(title: "high", priority: .p1, projectID: p.id)

        #expect(s.listOrder(project: p.id) == [high.id, low.id])
    }

    @Test func completedSubtasksAreLeftOut() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let a = s.addTask(title: "a", projectID: p.id)
        let sub = s.addTask(title: "sub", projectID: p.id, parentID: a.id)
        s.complete(sub)

        #expect(s.listOrder(project: p.id) == [a.id])
    }
}
