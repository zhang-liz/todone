import SwiftUI
import TodoneKit

/// Kanban-style board: one column per section (plus "No section"), drag between columns.
struct BoardView: View {
    @Environment(AppStore.self) private var store

    let projectID: UUID

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                BoardColumn(projectID: projectID, section: nil)
                ForEach(store.sections(in: projectID)) { section in
                    BoardColumn(projectID: projectID, section: section)
                }
                addSectionButton
            }
            .padding(16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var addSectionButton: some View {
        Button {
            store.addSection(name: "New Section", projectID: projectID)
        } label: {
            Label("Add section", systemImage: "plus")
                .padding(10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(width: 200, alignment: .leading)
        // Dropping a section column here moves it to the end.
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = SectionDrag.section(from: items, in: store),
                  dragged.projectID == projectID else { return false }
            store.reorderSection(dragged, before: nil)
            return true
        }
    }
}

private struct BoardColumn: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let projectID: UUID
    let section: ProjectSection?

    @State private var adding = false
    @State private var newText = ""
    @FocusState private var focused: Bool

    private var tasks: [TodoTask] {
        store.rootTasks(project: projectID, section: section?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        BoardCard(task: task)
                            .draggable(task.id.uuidString)
                    }
                }
            }
            .frame(minHeight: 60)

            if adding {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Task name", text: $newText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(submit)
                        .onExitCommand { adding = false }
                    HStack {
                        Button("Add") { submit() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Cancel") { adding = false }
                            .controlSize(.small)
                    }
                }
                .onAppear { focused = true }
            } else {
                Button {
                    adding = true
                } label: {
                    Label("Add task", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .dropDestination(for: String.self) { items, _ in
            // A dragged section column lands before this column.
            if let dragged = SectionDrag.section(from: items, in: store) {
                guard let section, dragged.id != section.id,
                      dragged.projectID == projectID else { return false }
                store.reorderSection(dragged, before: section)
                return true
            }
            guard let idString = items.first, let id = UUID(uuidString: idString),
                  let task = store.task(id) else { return false }
            store.reorder(task, before: nil, project: projectID, section: section?.id)
            return true
        }
    }

    @ViewBuilder
    private var header: some View {
        if let section {
            // Drag the column header to reorder sections; cards follow.
            headerContent.draggable(SectionDrag.payload(section))
        } else {
            headerContent
        }
    }

    private var headerContent: some View {
        HStack {
            Text(section?.name ?? "(No section)")
                .font(.headline)
            Text("\(tasks.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let section {
                Menu {
                    Button("Delete section", role: .destructive) {
                        store.deleteSection(section)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
            }
        }
        .contentShape(Rectangle())
    }

    private func submit() {
        let trimmed = newText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parsed = QuickAddParser().parse(trimmed)
        _ = store.addTask(title: parsed.title.isEmpty ? trimmed : parsed.title,
                          priority: parsed.priority,
                          dueDate: parsed.dueDate, hasDueTime: parsed.hasDueTime,
                          recurrence: parsed.recurrence?.displayText,
                          projectID: projectID, sectionID: section?.id)
        newText = ""
        focused = true
    }
}

private struct BoardCard: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let task: TodoTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    store.complete(task)
                } label: {
                    Circle()
                        .strokeBorder(task.priority.color, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .contentShape(Circle()) // ring-only hit area otherwise
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if let dueText = DueDateFormatter.text(for: task) {
                    Text(dueText)
                        .font(.caption)
                        .foregroundStyle(DueDateFormatter.color(for: task))
                }
                ForEach(task.labelIDs, id: \.self) { id in
                    if let label = store.label(id) {
                        Text("@\(label.name)")
                            .font(.caption)
                            .foregroundStyle(Color(label.color))
                    }
                }
                Spacer()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedTaskID = task.id }
    }
}
