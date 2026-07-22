import Foundation
import TodoneKit

/// First-run sample content so the app doesn't open empty.
enum SampleData {
    static func installIfEmpty(into store: AppStore) {
        guard store.tasks.isEmpty, store.projects.filter({ !$0.isInbox }).isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let welcome = store.addProject(name: "Welcome 👋", color: .blue)
        let learn = store.addSection(name: "Learn the basics", projectID: welcome.id)
        let power = store.addSection(name: "Power features", projectID: welcome.id)

        store.addTask(title: "Click the circle to complete a task",
                      projectID: welcome.id, sectionID: learn.id)
        store.addTask(title: "Click a task to open its details",
                      details: "Edit dates, priority, labels, reminders, and subtasks there.",
                      projectID: welcome.id, sectionID: learn.id)
        store.addTask(title: "Add a task with ⌘N — try typing \"Call mom tomorrow 5pm p2\"",
                      priority: .p2, projectID: welcome.id, sectionID: learn.id)

        store.addTask(title: "Try the board view (toolbar icon)",
                      projectID: welcome.id, sectionID: power.id)
        store.addTask(title: "Make a filter — \"today & p1\" in Filters & Labels",
                      projectID: welcome.id, sectionID: power.id)
        store.addTask(title: "Search everything with ⌘K",
                      projectID: welcome.id, sectionID: power.id)

        let errands = store.addLabel(name: "errands", color: .green)
        let home = store.addLabel(name: "home", color: .orange)

        store.addTask(title: "Water the plants", dueDate: today, recurrence: "every 3 days",
                      projectID: store.inbox.id, labelIDs: [home.id])
        store.addTask(title: "Pick up groceries", priority: .p3, dueDate: today,
                      projectID: store.inbox.id, labelIDs: [errands.id])
        store.addTask(title: "Plan the weekend trip", priority: .p2,
                      dueDate: cal.date(byAdding: .day, value: 2, to: today),
                      projectID: store.inbox.id)

        store.addFilter(name: "Priority 1", query: "p1", color: .red)
        store.addFilter(name: "Next 7 days", query: "7 days", color: .violet)

        store.saveNow()
    }
}
