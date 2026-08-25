import SwiftUI
import TodoneKit

/// A single task row: priority-colored checkbox, title, meta line, hover actions.
struct TaskRowView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let task: TodoTask
    /// Show the project breadcrumb (Today/Upcoming/filter lists).
    var showsProject = false
    var indent = 0

    @State private var hovering = false
    @State private var completing = false
    @State private var showScheduler = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(completing || task.isCompleted)
                    .foregroundStyle(completing || task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                metaLine
            }

            Spacer(minLength: 0)

            if hovering && !task.isCompleted {
                hoverActions
            }
        }
        .padding(.leading, CGFloat(indent) * 24)
        .padding(.vertical, 6)
        .background(
            model.taskSelection.contains(task.id)
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Modifier-aware taps come first: SwiftUI matches the most specific
        // gesture, so the plain tap below only fires with no modifiers held.
        .onTapGesture {
            model.handleClick(on: task.id, extending: false, toggling: false)
        }
        .modifier(ModifierClicks(
            onShift: { model.handleClick(on: task.id, extending: true, toggling: false) },
            onCommand: { model.handleClick(on: task.id, extending: false, toggling: true) }
        ))
        .contextMenu { contextMenuContent }
        .popover(isPresented: $showScheduler) {
            SchedulePopover(task: task)
        }
    }

    // MARK: - Checkbox

    private var checkbox: some View {
        Button {
            completeWithDelay()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(task.priority.color, lineWidth: 1.5)
                    .background(
                        Circle().fill(task.priority == .p4 ? Color.clear : task.priority.color.opacity(0.12))
                    )
                    .frame(width: 18, height: 18)
                if completing || task.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(task.priority.color)
                }
            }
            // A stroked circle is only hit-testable on its ring, so clicks in
            // the empty middle fell through to the row's tap gesture (select)
            // instead of completing. Make the whole disc clickable.
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(task.recurrence != nil ? "Complete (advances recurrence)" : "Complete")
    }

    private func completeWithDelay() {
        guard !task.isCompleted else {
            store.uncomplete(task)
            return
        }
        guard !completing else { return }
        completing = true
        // Brief fill-then-fade like Todoist.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.2)) {
                // The task may have been deleted during the animation window.
                if store.task(task.id) != nil {
                    store.complete(task)
                    if model.selectedTaskID == task.id { model.selectedTaskID = nil }
                }
                completing = false
            }
        }
    }

    // MARK: - Meta

    private var metaLine: some View {
        HStack(spacing: 8) {
            if let dueText = DueDateFormatter.text(for: task) {
                Button { showScheduler = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: task.recurrence != nil ? "arrow.triangle.2.circlepath" : "calendar")
                            .font(.system(size: 9))
                        Text(dueText)
                    }
                    .font(.caption)
                    .foregroundStyle(DueDateFormatter.color(for: task))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change due date")
            }

            ForEach(task.labelIDs, id: \.self) { id in
                if let label = store.label(id) {
                    HStack(spacing: 2) {
                        Image(systemName: "tag")
                            .font(.system(size: 8))
                        Text(label.name)
                    }
                    .font(.caption)
                    .foregroundStyle(Color(label.color))
                }
            }

            let subCount = store.subtasks(of: task.id).count
            if subCount > 0 {
                let done = store.subtasks(of: task.id).filter(\.isCompleted).count
                HStack(spacing: 2) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                    Text("\(done)/\(subCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !task.details.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if showsProject {
                Spacer()
                if let project = store.project(task.projectID) {
                    HStack(spacing: 3) {
                        Text(breadcrumb(project))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(Color(project.color))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
    }

    private func breadcrumb(_ project: Project) -> String {
        if let sid = task.sectionID, let section = store.section(sid) {
            return "\(project.name) / \(section.name)"
        }
        return project.name
    }

    // MARK: - Hover actions

    private var hoverActions: some View {
        HStack(spacing: 8) {
            Button { showScheduler = true } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.plain)
            .help("Schedule")

            Button { model.selectedTaskID = task.id } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit")

            Menu {
                contextMenuContent
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .foregroundStyle(.secondary)
    }

    /// Tasks a menu action applies to: the whole selection when this row is
    /// part of it, otherwise just this row.
    private var actionTargets: [TodoTask] {
        guard model.taskSelection.count > 1, model.taskSelection.contains(task.id) else {
            return [task]
        }
        return model.visibleTaskIDs
            .filter { model.taskSelection.contains($0) }
            .compactMap { store.task($0) }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if actionTargets.count > 1 {
            bulkMenuContent
        } else {
            singleMenuContent
        }
    }

    @ViewBuilder
    private var bulkMenuContent: some View {
        Group {
            let n = actionTargets.count
            Button("Complete \(n) Tasks") {
                store.asSingleUndoStep { for t in actionTargets { store.complete(t) } }
                model.taskSelection.clear()
            }
            Button("Due Today (\(n))") {
                store.asSingleUndoStep {
                    for t in actionTargets {
                        store.updateTask(t) { task in
                            task.dueDate = Calendar.current.startOfDay(for: Date())
                            task.hasDueTime = false
                        }
                    }
                }
            }
            Menu("Priority (\(n))") {
                ForEach(Priority.allCases, id: \.rawValue) { p in
                    Button("Priority \(p.rawValue)") {
                        store.asSingleUndoStep {
                            for t in actionTargets { store.updateTask(t) { $0.priority = p } }
                        }
                    }
                }
            }
            Menu("Move \(n) to") {
                ForEach(store.projects.filter { !$0.isArchived }) { project in
                    Button(project.name) {
                        store.asSingleUndoStep {
                            for t in actionTargets { store.move(t, toProject: project.id, section: nil) }
                        }
                    }
                }
            }
            Divider()
            Button("Delete \(n) Tasks", role: .destructive) {
                store.asSingleUndoStep { for t in actionTargets { store.deleteTask(t) } }
                model.taskSelection.clear()
            }
        }
    }

    @ViewBuilder
    private var singleMenuContent: some View {
        Button("Edit") { model.selectedTaskID = task.id }
        Button("Schedule…") { showScheduler = true }

        Menu("Priority") {
            ForEach(Priority.allCases, id: \.rawValue) { p in
                Button {
                    store.updateTask(task) { $0.priority = p }
                } label: {
                    Label("Priority \(p.rawValue)", systemImage: task.priority == p ? "checkmark" : "flag")
                }
            }
        }

        Menu("Move to") {
            ForEach(store.projects.filter { !$0.isArchived }) { project in
                Button(project.name) {
                    store.move(task, toProject: project.id, section: nil)
                }
            }
        }

        Menu("Labels") {
            ForEach(store.labels) { label in
                Button {
                    store.updateTask(task) { t in
                        if t.labelIDs.contains(label.id) {
                            t.labelIDs.removeAll { $0 == label.id }
                        } else {
                            t.labelIDs.append(label.id)
                        }
                    }
                } label: {
                    if task.labelIDs.contains(label.id) {
                        Label(label.name, systemImage: "checkmark")
                    } else {
                        Text(label.name)
                    }
                }
            }
        }

        Button("Add Subtask") {
            let sub = store.addTask(title: "New subtask", projectID: task.projectID,
                                    sectionID: task.sectionID, parentID: task.id)
            model.selectedTaskID = sub.id
        }

        Divider()

        Button("Duplicate") {
            store.addTask(title: task.title, details: task.details, priority: task.priority,
                          dueDate: task.dueDate, hasDueTime: task.hasDueTime,
                          recurrence: task.recurrence, projectID: task.projectID,
                          sectionID: task.sectionID, parentID: task.parentID,
                          labelIDs: task.labelIDs)
        }

        Button("Delete", role: .destructive) {
            if model.selectedTaskID == task.id { model.selectedTaskID = nil }
            store.deleteTask(task)
        }
    }
}

/// Quick reschedule popover: Today / Tomorrow / Next week / date picker.
struct SchedulePopover: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let task: TodoTask
    @State private var pickedDate: Date

    init(task: TodoTask) {
        self.task = task
        _pickedDate = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text = DueDateFormatter.text(for: task) {
                Text("Due \(text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
            }
            quickButton("Today", icon: "calendar", date: Date())
            quickButton("Tomorrow", icon: "sun.max",
                        date: Calendar.current.date(byAdding: .day, value: 1, to: Date()))
            quickButton("Next Week", icon: "calendar.badge.clock",
                        date: nextMonday())
            Divider()
            DatePicker("Date", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .frame(width: 220)
            HStack {
                Button("No Date") {
                    store.reschedule(task, toDay: nil)
                    dismiss()
                }
                Spacer()
                Button("Set") {
                    store.reschedule(task, toDay: pickedDate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func quickButton(_ title: String, icon: String, date: Date?) -> some View {
        Button {
            if let date {
                store.reschedule(task, toDay: date)
            }
            dismiss()
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func nextMonday() -> Date? {
        let cal = Calendar.current
        var d = cal.startOfDay(for: Date())
        for _ in 0..<8 {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            if cal.component(.weekday, from: d) == 2 { return d }
        }
        return nil
    }
}

/// Shift-click and cmd-click handlers for a row.
///
/// `onTapGesture` carries no modifier information, so the two modified cases
/// are attached as their own gestures. SwiftUI prefers the more specific match,
/// leaving the plain tap for unmodified clicks.
private struct ModifierClicks: ViewModifier {
    let onShift: () -> Void
    let onCommand: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().modifiers(.shift).onEnded(onShift)
            )
            .simultaneousGesture(
                TapGesture().modifiers(.command).onEnded(onCommand)
            )
    }
}
