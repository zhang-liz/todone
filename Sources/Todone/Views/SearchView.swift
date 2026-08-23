import SwiftUI
import TodoneKit

/// Command-palette style search over tasks and projects.
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tasks and projects…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onExitCommand { dismiss() }
            }
            .padding(14)

            Divider()

            List {
                let (taskHits, projectHits) = results
                if !taskHits.isEmpty {
                    Section("Tasks") {
                        ForEach(taskHits) { task in
                            Button {
                                open(task)
                            } label: {
                                HStack {
                                    if task.isCompleted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Circle()
                                            .strokeBorder(task.priority.color, lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(task.title)
                                            .strikethrough(task.isCompleted)
                                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                        if let p = store.project(task.projectID) {
                                            Text(p.isInbox ? "Inbox" : p.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if let dueText = DueDateFormatter.text(for: task) {
                                        Text(dueText)
                                            .font(.caption)
                                            .foregroundStyle(DueDateFormatter.color(for: task))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !projectHits.isEmpty {
                    Section("Projects") {
                        ForEach(projectHits) { project in
                            Button {
                                model.select(.project(project.id))
                                dismiss()
                            } label: {
                                Label(project.name, systemImage: "number")
                                    .foregroundStyle(Color(project.color))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if taskHits.isEmpty && projectHits.isEmpty && !query.isEmpty {
                    Text("No results for \"\(query)\"")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 560, height: 420)
        .onAppear { focused = true }
    }

    private var results: ([TodoTask], [Project]) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ([], []) }
        func matches(_ t: TodoTask) -> Bool {
            t.title.lowercased().contains(q) || t.details.lowercased().contains(q)
        }
        // Completed tasks are searchable but rank last, so finishing something
        // does not make it unfindable while live results stay on top.
        let open = store.incompleteTasks.filter(matches)
        let done = store.tasks
            .filter { $0.isCompleted && matches($0) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let tasks = (open + done).prefix(30)
        let projects = store.projects
            .filter { !$0.isArchived && !$0.isInbox && $0.name.lowercased().contains(q) }
            .prefix(10)
        return (Array(tasks), Array(projects))
    }

    private func open(_ task: TodoTask) {
        if task.isCompleted {
            // A project list hides completed tasks unless the toggle is on, so
            // land somewhere the result is actually visible.
            model.select(.completed)
        } else if let p = store.project(task.projectID) {
            model.select(p.isInbox ? .inbox : .project(p.id))
        }
        model.selectedTaskID = task.id
        dismiss()
    }
}
