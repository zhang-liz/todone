import SwiftUI
import TodoneKit

/// Trailing inspector with the full task editor.
struct TaskDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selectedTaskID, let task = store.task(id) {
            TaskDetailForm(task: task)
                .id(task.id)
        } else {
            ContentUnavailableView("No task selected", systemImage: "square.dashed")
        }
    }
}

private struct TaskDetailForm: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let task: TodoTask

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var dateText: String = ""
    @State private var dateFeedback: String?
    @State private var showScheduler = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                TextField("Task name", text: $title, axis: .vertical)
                    .font(.title3.weight(.medium))
                    .textFieldStyle(.plain)
                    .onSubmit(saveTitle)

                TextField("Description", text: $details, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.secondary)
                    .onSubmit(saveDetails)

                Divider()

                projectPicker
                dueDateEditor
                priorityPicker
                labelEditor
                reminderEditor

                Divider()

                subtaskList
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(role: .destructive) {
                    model.selectedTaskID = nil
                    store.deleteTask(task)
                } label: {
                    Image(systemName: "trash")
                }
                Spacer()
                Button("Done") {
                    saveTitle()
                    saveDetails()
                    model.selectedTaskID = nil
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(10)
            .background(.bar)
        }
        .onAppear {
            title = task.title
            details = task.details
            dateText = ""
        }
        .onDisappear {
            saveTitle()
            saveDetails()
        }
    }

    private var header: some View {
        HStack {
            Button {
                store.complete(task)
                model.selectedTaskID = nil
            } label: {
                Label(task.recurrence != nil ? "Complete occurrence" : "Complete",
                      systemImage: "checkmark.circle")
            }
            Spacer()
            if task.isCompleted {
                Button("Uncomplete") { store.uncomplete(task) }
            }
        }
    }

    private var projectPicker: some View {
        LabeledContent("Project") {
            Picker("", selection: Binding(
                get: { task.projectID },
                set: { store.move(task, toProject: $0, section: nil) }
            )) {
                ForEach(store.projects.filter { !$0.isArchived }) { p in
                    Text(p.isInbox ? "Inbox" : p.name).tag(p.id)
                }
            }
            .labelsHidden()

            let sections = store.sections(in: task.projectID)
            if !sections.isEmpty {
                Picker("", selection: Binding(
                    get: { task.sectionID },
                    set: { sid in
                        store.updateTask(task) { $0.sectionID = sid }
                    }
                )) {
                    Text("No section").tag(UUID?.none)
                    ForEach(sections) { s in
                        Text(s.name).tag(UUID?.some(s.id))
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var dueDateEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Due") {
                HStack(spacing: 6) {
                    Button { showScheduler = true } label: {
                        if let text = DueDateFormatter.text(for: task) {
                            Label(text, systemImage: "calendar")
                                .foregroundStyle(DueDateFormatter.color(for: task))
                        } else {
                            Label("Add date", systemImage: "calendar.badge.plus")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Change due date")
                    .popover(isPresented: $showScheduler) {
                        SchedulePopover(task: task)
                    }
                    if let r = task.recurrence {
                        Label(r, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if task.dueDate != nil {
                        Button {
                            store.reschedule(task, toDay: nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove due date")
                    }
                }
            }

            TextField("Or type a date — \"tomorrow 3pm\", \"every friday\"…", text: $dateText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(applyDateText)

            if let feedback = dateFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func applyDateText() {
        let trimmed = dateText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parsed = QuickAddParser().parse(trimmed)
        if parsed.dueDate == nil && parsed.recurrence == nil {
            dateFeedback = "Couldn't understand \"\(trimmed)\""
            return
        }
        dateFeedback = nil
        store.updateTask(task) {
            if let due = parsed.dueDate {
                $0.dueDate = due
                $0.hasDueTime = parsed.hasDueTime
            }
            $0.recurrence = parsed.recurrence?.displayText ?? $0.recurrence
        }
        dateText = ""
    }

    private var priorityPicker: some View {
        LabeledContent("Priority") {
            HStack(spacing: 6) {
                ForEach(Priority.allCases, id: \.rawValue) { p in
                    Button {
                        store.updateTask(task) { $0.priority = p }
                    } label: {
                        Image(systemName: task.priority == p ? "flag.fill" : "flag")
                            .foregroundStyle(p.color)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(task.priority == p ? p.color.opacity(0.15) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Priority \(p.rawValue) (⌥\(p.rawValue))")
                }
            }
        }
    }

    private var labelEditor: some View {
        LabeledContent("Labels") {
            Menu {
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
            } label: {
                if task.labelIDs.isEmpty {
                    Text("Add labels")
                } else {
                    Text(task.labelIDs.compactMap { store.label($0)?.name }.joined(separator: ", "))
                }
            }
        }
    }

    private var reminderEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Reminders") {
                Menu("Add") {
                    if task.dueDate != nil && task.hasDueTime {
                        Button("At due time") {
                            store.addReminder(taskID: task.id, kind: .relative(minutesBefore: 0))
                        }
                        Button("10 minutes before") {
                            store.addReminder(taskID: task.id, kind: .relative(minutesBefore: 10))
                        }
                        Button("1 hour before") {
                            store.addReminder(taskID: task.id, kind: .relative(minutesBefore: 60))
                        }
                    }
                    Button("Tomorrow 9 AM") {
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                        comps.day = (comps.day ?? 1) + 1
                        comps.hour = 9
                        if let d = Calendar.current.date(from: comps) {
                            store.addReminder(taskID: task.id, kind: .absolute(d))
                        }
                    }
                }
            }

            ForEach(store.reminders(for: task.id)) { reminder in
                HStack {
                    Image(systemName: "bell")
                    Text(reminderText(reminder))
                        .font(.callout)
                    Spacer()
                    Button {
                        store.deleteReminder(reminder)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func reminderText(_ reminder: TaskReminder) -> String {
        switch reminder.kind {
        case .absolute(let date):
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: date)
        case .relative(let minutes):
            if minutes == 0 { return "At due time" }
            if minutes % 60 == 0 { return "\(minutes / 60)h before due" }
            return "\(minutes)m before due"
        }
    }

    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subtasks")
                .font(.headline)
            ForEach(store.subtasks(of: task.id)) { sub in
                TaskRowView(task: sub)
            }
            Button {
                let sub = store.addTask(title: "New subtask", projectID: task.projectID,
                                        sectionID: task.sectionID, parentID: task.id)
                model.selectedTaskID = sub.id
            } label: {
                Label("Add subtask", systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != task.title {
            store.updateTask(task) { $0.title = trimmed }
        }
    }

    private func saveDetails() {
        if details != task.details {
            store.updateTask(task) { $0.details = details }
        }
    }
}
