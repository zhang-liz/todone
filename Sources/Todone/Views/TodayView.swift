import SwiftUI
import TodoneKit

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var adding = false

    var body: some View {
        let overdue = store.overdueTasks().filter { !Calendar.current.isDateInToday($0.dueDate ?? Date()) }
        let today = store.tasksDue(on: Date())

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !overdue.isEmpty {
                    HStack {
                        Text("Overdue")
                            .font(.headline)
                        Spacer()
                        Button("Reschedule all to Today") {
                            for t in overdue {
                                store.updateTask(t) { task in
                                    task.dueDate = Calendar.current.startOfDay(for: Date())
                                    task.hasDueTime = false
                                }
                            }
                        }
                        .font(.callout)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    ForEach(overdue) { task in
                        TaskRowView(task: task, showsProject: true)
                            .padding(.horizontal, 20)
                        Divider().padding(.leading, 48)
                    }
                }

                HStack {
                    Text(todayHeader)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if today.isEmpty && overdue.isEmpty {
                    ContentUnavailableView {
                        Label("All clear", systemImage: "checkmark.circle")
                    } description: {
                        Text("Enjoy your day — nothing due today.")
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(today) { task in
                        TaskRowView(task: task, showsProject: true)
                            .padding(.horizontal, 20)
                        Divider().padding(.leading, 48)
                    }
                }

                if adding {
                    TodayInlineAdd(isPresented: $adding)
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
                    .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Today")
        .inspector(isPresented: Binding(
            get: { model.selectedTaskID != nil },
            set: { if !$0 { model.selectedTaskID = nil } }
        )) {
            TaskDetailView()
        }
    }

    private var todayHeader: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return "Today ∙ \(f.string(from: Date()))"
    }
}

/// Inline add on Today: defaults the due date to today.
private struct TodayInlineAdd: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Binding var isPresented: Bool

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Task name", text: $text)
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
        var parsed = QuickAddParser().parse(trimmed)
        if parsed.dueDate == nil {
            parsed.dueDate = Calendar.current.startOfDay(for: Date())
        }
        _ = store.addTask(from: parsed)
        text = ""
        focused = true
    }
}
