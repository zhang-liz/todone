import Foundation
import Testing
@testable import TodoneKit

@Suite struct OpenTaskCountTests {
    // The Inbox badge left out subtasks and tasks in sections, but project badges
    // counted them. Project badges also counted subtasks the list does not show.
    @Test func countMatchesTheRowsInTheList() {
        let s = AppStore()
        let inbox = s.inbox
        let section = s.addSection(name: "Later", projectID: inbox.id)
        let parent = s.addTask(title: "parent", projectID: inbox.id)
        s.addTask(title: "sub", projectID: inbox.id, parentID: parent.id)
        s.addTask(title: "in section", projectID: inbox.id, sectionID: section.id)

        #expect(s.openTaskCount(project: inbox.id) == 3)
        #expect(s.openTaskCount(project: inbox.id) == s.listOrder(project: inbox.id).count)
        #expect(s.openTaskCount(project: inbox.id, section: section.id) == 1)
        #expect(s.openTaskCount(project: inbox.id, section: nil) == 2)
    }

    @Test func subtaskOfACompletedTaskIsNotCounted() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let parent = s.addTask(title: "parent", projectID: p.id)
        s.addTask(title: "sub", projectID: p.id, parentID: parent.id)
        s.complete(parent)

        #expect(s.openTaskCount(project: p.id) == 0)
        #expect(s.listOrder(project: p.id).isEmpty)
    }

    @Test func subtasksBelowTheFourthLevelAreNotCounted() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        var parent = s.addTask(title: "root", projectID: p.id)
        for level in 1...6 {
            parent = s.addTask(title: "level \(level)", projectID: p.id, parentID: parent.id)
        }

        #expect(s.openTaskCount(project: p.id) == 5)
        #expect(s.openTaskCount(project: p.id) == s.listOrder(project: p.id).count)
    }
}
