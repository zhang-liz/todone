import SwiftUI
import TodoneKit

/// Date-grouped scrolling list of the next weeks + a month strip for jumping.
struct UpcomingView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme

    @State private var anchorDay = Calendar.current.startOfDay(for: Date())
    @State private var daysShown = 30
    @State private var addingDay: Date?

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            monthStrip
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        overdueBlock

                        ForEach(0..<daysShown, id: \.self) { offset in
                            if let day = calendar.date(byAdding: .day, value: offset, to: anchorDay) {
                                dayBlock(day)
                                    .id(dayKey(day))
                            }
                        }

                        Button("Show more days") { daysShown += 30 }
                            .padding(20)
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: anchorDay) {
                    proxy.scrollTo(dayKey(anchorDay), anchor: .top)
                }
            }
        }
        .navigationTitle("Upcoming")
        .inspector(isPresented: Binding(
            get: { model.selectedTaskID != nil },
            set: { if !$0 { model.selectedTaskID = nil } }
        )) {
            TaskDetailView()
        }
    }

    private func dayKey(_ day: Date) -> String {
        KarmaEngine.dayKey(for: day, calendar: calendar)
    }

    // MARK: - Month strip

    private var monthStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<60, id: \.self) { offset in
                    if let day = calendar.date(byAdding: .day, value: offset,
                                               to: calendar.startOfDay(for: Date())) {
                        dayCell(day)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: anchorDay)
        let count = store.tasksDue(on: day).count
        let weekdayF = DateFormatter()
        weekdayF.dateFormat = "EEE"

        return Button {
            anchorDay = day
        } label: {
            VStack(spacing: 2) {
                Text(weekdayF.string(from: day))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(isSelected ? .bold : .regular))
                Circle()
                    .fill(count > 0 ? theme.accent : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 36, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.accent.opacity(0.15) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Blocks

    @ViewBuilder
    private var overdueBlock: some View {
        let overdue = store.overdueTasks().filter { !calendar.isDateInToday($0.dueDate ?? Date()) }
        if !overdue.isEmpty {
            HStack {
                Text("Overdue").font(.headline).foregroundStyle(.red)
                Spacer()
                Button("Reschedule all to Today") {
                    for t in overdue {
                        store.updateTask(t) { task in
                            task.dueDate = calendar.startOfDay(for: Date())
                            task.hasDueTime = false
                        }
                    }
                }
                .font(.callout)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            ForEach(overdue) { task in
                TaskRowView(task: task, showsProject: true)
                    .padding(.horizontal, 20)
                Divider().padding(.leading, 48)
            }
        }
    }

    private func dayBlock(_ day: Date) -> some View {
        let tasks = store.tasksDue(on: day)
        return VStack(alignment: .leading, spacing: 0) {
            Text(headerText(day))
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ForEach(tasks) { task in
                TaskRowView(task: task, showsProject: true)
                    .padding(.horizontal, 20)
                Divider().padding(.leading, 48)
            }

            if addingDay == day {
                UpcomingInlineAdd(day: day, isPresented: Binding(
                    get: { addingDay == day },
                    set: { if !$0 { addingDay = nil } }
                ))
                .padding(.horizontal, 20)
            } else {
                Button {
                    addingDay = day
                } label: {
                    Label("Add task", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
    }

    private func headerText(_ day: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d ∙ EEEE"
        let base = f.string(from: day)
        if calendar.isDateInToday(day) { return "\(f.string(from: day)) ∙ Today" }
        if calendar.isDateInTomorrow(day) { return "\(f.string(from: day)) ∙ Tomorrow" }
        return base
    }
}

private struct UpcomingInlineAdd: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme

    let day: Date
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
            parsed.dueDate = day
        }
        _ = store.addTask(from: parsed)
        text = ""
    }
}
