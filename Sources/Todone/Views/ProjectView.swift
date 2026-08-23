import SwiftUI
import TodoneKit

/// A project's task list (list or board style) with sections and inline add.
struct ProjectView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let projectID: UUID

    @State private var showCompleted = false
    @State private var renamingSection: ProjectSection?

    private var project: Project? { store.project(projectID) }

    var body: some View {
        Group {
            if let project {
                if project.viewStyle == .board {
                    BoardView(projectID: projectID)
                } else {
                    listBody(project)
                }
            } else {
                ContentUnavailableView("Project not found", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(project?.isInbox == true ? "Inbox" : project?.name ?? "")
        .onAppear { model.visibleTaskIDs = visibleOrder }
        .onChange(of: visibleOrder) { _, ids in model.visibleTaskIDs = ids }
        .toolbar { toolbarContent }
        .inspector(isPresented: Binding(
            get: { model.selectedTaskID != nil },
            set: { if !$0 { model.selectedTaskID = nil } }
        )) {
            TaskDetailView()
        }
    }

    /// Task IDs in the order the list renders them: unsectioned first, then each
    /// section in turn. Mirrors `listBody` so keyboard navigation follows what
    /// is actually on screen.
    private var visibleOrder: [UUID] {
        var ids = store.rootTasks(project: projectID, section: nil).map(\.id)
        for section in store.sections(in: projectID) {
            ids += store.rootTasks(project: projectID, section: section.id).map(\.id)
        }
        return ids
    }

    private func listBody(_ project: Project) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                // Tasks without a section.
                TaskGroupView(projectID: projectID, sectionID: nil, showsHeader: false)

                ForEach(store.sections(in: projectID)) { section in
                    SectionHeaderView(section: section, renaming: $renamingSection)
                    TaskGroupView(projectID: projectID, sectionID: section.id, showsHeader: true)
                }

                Button {
                    let s = store.addSection(name: "New Section", projectID: projectID)
                    renamingSection = s
                } label: {
                    Label("Add section", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if showCompleted {
                    completedList
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var completedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Completed")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            ForEach(store.completedTasks(project: projectID)) { task in
                TaskRowView(task: task)
                    .padding(.horizontal, 20)
                    .opacity(0.6)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if let project, !project.isInbox {
                Button {
                    project.viewStyle = project.viewStyle == .list ? .board : .list
                    store.scheduleSave()
                } label: {
                    Image(systemName: project.viewStyle == .list
                          ? "rectangle.split.3x1" : "list.bullet")
                }
                .help(project.viewStyle == .list ? "Board view" : "List view")
            }

            if let project {
                Menu {
                    Picker("Sort by", selection: Binding(
                        get: { project.taskSort },
                        set: { project.taskSort = $0; store.scheduleSave() }
                    )) {
                        ForEach(TaskSort.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Divider()
                    Picker("Group by", selection: Binding(
                        get: { project.grouping },
                        set: { project.grouping = $0; store.scheduleSave() }
                    )) {
                        ForEach(TaskGrouping.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Sort and group")
            }

            Toggle(isOn: $showCompleted) {
                Image(systemName: "checkmark.circle")
            }
            .help("Show completed tasks")

            Button {
                model.showQuickAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Add task (Q)")
        }
    }
}

/// The incomplete root tasks for one (project, section) bucket + inline add row.
struct TaskGroupView: View {
    @Environment(AppStore.self) private var store

    let projectID: UUID
    let sectionID: UUID?
    let showsHeader: Bool

    @State private var adding = false

    var body: some View {
        let tasks = store.rootTasks(project: projectID, section: sectionID)
        let grouping = store.project(projectID)?.grouping ?? .none
        let groups = TaskSorter.grouped(tasks, by: grouping,
                                        calendar: store.calendar,
                                        projectName: { store.project($0)?.name })
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                if !group.title.isEmpty {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
                ForEach(group.tasks) { task in
                    VStack(alignment: .leading, spacing: 0) {
                        TaskRowView(task: task)
                            .draggable(task.id.uuidString)
                        SubtaskListView(parentID: task.id, depth: 1)
                    }
                    .padding(.horizontal, 20)
                    // Dropping onto a row inserts before that row.
                    .dropDestination(for: String.self) { items, _ in
                        handleDrop(items, before: task)
                    }
                    Divider().padding(.leading, 48)
                }
            }

            if adding {
                InlineAddRow(projectID: projectID, sectionID: sectionID, isPresented: $adding)
                    .padding(.horizontal, 20)
            } else {
                Button {
                    adding = true
                } label: {
                    Label("Add task", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, before: nil)
        }
    }

    private func handleDrop(_ items: [String], before: TodoTask?) -> Bool {
        guard let idString = items.first, let id = UUID(uuidString: idString),
              let task = store.task(id), task.id != before?.id else { return false }
        store.reorder(task, before: before, project: projectID, section: sectionID)
        return true
    }
}

/// Recursive subtask list, indented.
struct SubtaskListView: View {
    @Environment(AppStore.self) private var store
    let parentID: UUID
    let depth: Int

    var body: some View {
        let subs = store.subtasks(of: parentID, includeCompleted: false)
        ForEach(subs) { sub in
            TaskRowView(task: sub, indent: min(depth, 4))
            if depth < 4 {
                SubtaskListView(parentID: sub.id, depth: depth + 1)
            }
        }
    }
}

struct SectionHeaderView: View {
    @Environment(AppStore.self) private var store
    let section: ProjectSection
    @Binding var renaming: ProjectSection?

    @State private var name = ""

    var body: some View {
        HStack {
            if renaming?.id == section.id {
                TextField("Section name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .onSubmit {
                        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                            section.name = name
                            store.scheduleSave()
                        }
                        renaming = nil
                    }
                    .onAppear { name = section.name }
            } else {
                Text(section.name)
                    .font(.headline)
            }
            Text("\(store.rootTasks(project: section.projectID, section: section.id).count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Rename") { renaming = section }
                Button("Delete", role: .destructive) { store.deleteSection(section) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

/// Inline task entry with quick-add parsing (dates, priority, labels).
struct InlineAddRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme

    let projectID: UUID
    let sectionID: UUID?
    @Binding var isPresented: Bool

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Task name (try \"tomorrow 3pm p1 @label\")", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand { isPresented = false }

            QuickAddTokenPreview(text: text)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add task") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent.opacity(0.5)))
        .padding(.vertical, 6)
        .onAppear { focused = true }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parsed = QuickAddParser().parse(trimmed)
        var adjusted = parsed
        // Inline add stays in this project/section unless #project was typed.
        if parsed.projectName == nil {
            _ = store.addTask(title: parsed.title.isEmpty ? trimmed : parsed.title,
                              priority: parsed.priority,
                              dueDate: parsed.dueDate, hasDueTime: parsed.hasDueTime,
                              recurrence: parsed.recurrence?.displayText,
                              projectID: projectID, sectionID: sectionID,
                              labelIDs: resolveLabels(parsed.labelNames))
        } else {
            _ = store.addTask(from: adjusted)
        }
        text = ""
        focused = true
    }

    private func resolveLabels(_ names: [String]) -> [UUID] {
        names.map { store.addLabel(name: $0).id }
    }
}

/// Small legend under quick-add fields showing what got parsed.
struct QuickAddTokenPreview: View {
    let text: String

    var body: some View {
        let parsed = QuickAddParser().parse(text)
        HStack(spacing: 8) {
            if let due = parsed.dueDate {
                chip(icon: "calendar",
                     text: DueDateFormatter.dayText(for: due) + (parsed.hasDueTime ? timeSuffix(due) : ""),
                     color: .green)
            }
            if let rule = parsed.recurrence {
                chip(icon: "arrow.triangle.2.circlepath", text: rule.displayText, color: .purple)
            }
            if parsed.priority != .p4 {
                chip(icon: "flag.fill", text: parsed.priority.displayName, color: parsed.priority.color)
            }
            if let p = parsed.projectName {
                chip(icon: "number", text: p, color: .blue)
            }
            if let s = parsed.sectionName {
                chip(icon: "square.split.2x1", text: s, color: .teal)
            }
            ForEach(parsed.labelNames, id: \.self) { l in
                chip(icon: "tag", text: l, color: .orange)
            }
        }
        .frame(minHeight: parsed.tokens.isEmpty ? 0 : nil)
    }

    private func timeSuffix(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return " " + f.string(from: date)
    }

    private func chip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }
}
