import Testing
@testable import TodoneKit

@Suite struct InlineAddTests {
    @Test func plainTextStaysInTheRowsProjectAndSection() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let row = s.addSection(name: "Doing", projectID: p.id)

        let t = s.addTask(from: QuickAddParser().parse("Write report"),
                          defaultProjectID: p.id, defaultSectionID: row.id)

        #expect(t.projectID == p.id)
        #expect(t.sectionID == row.id)
    }

    // Board and project rows ignored /section, and Board also dropped @label and #project.
    @Test func typedSectionReplacesTheRowsSection() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let row = s.addSection(name: "Doing", projectID: p.id)
        let design = s.addSection(name: "Design", projectID: p.id)

        let t = s.addTask(from: QuickAddParser().parse("Logo /Design"),
                          defaultProjectID: p.id, defaultSectionID: row.id)

        #expect(t.title == "Logo")
        #expect(t.sectionID == design.id)
    }

    @Test func typedLabelIsKeptAndNotDuplicated() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let home = s.addLabel(name: "home")

        let t = s.addTask(from: QuickAddParser().parse("Logo @home"), defaultProjectID: p.id)

        #expect(t.labelIDs == [home.id])
        #expect(s.labels.count == 1)
    }

    @Test func typedProjectDropsTheRowsSection() {
        let s = AppStore()
        let p = s.addProject(name: "Work")
        let other = s.addProject(name: "Home")
        let row = s.addSection(name: "Doing", projectID: p.id)

        let t = s.addTask(from: QuickAddParser().parse("Logo #Home"),
                          defaultProjectID: p.id, defaultSectionID: row.id)

        #expect(t.projectID == other.id)
        #expect(t.sectionID == nil)
    }
}
