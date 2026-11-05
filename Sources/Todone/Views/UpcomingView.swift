import SwiftUI
import TodoneKit

/// Date-grouped scrolling list of the next weeks + a month strip for jumping.
struct UpcomingView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme

    /// The list always starts today, so a jump does not hide the days before it.
    @State private var firstDay = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var daysShown = Self.stripDays
    @State private var addingDay: Date?

    /// Every day in the month strip is also in the list, so a jump always lands.
    private static let stripDays = 60

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                monthStrip(proxy)
                Divider()
                ScrollView {
                    // Not lazy: scrollTo cannot be relied on to find a row that is not built yet.
                    VStack(alignment: .leading, spacing: 0) {
                        overdueBlock

                        ForEach(0..<daysShown, id: \.self) { offset in
                            if let day = calendar.date(byAdding: .day, value: offset, to: firstDay) {
                                dayBlock(day)
                                    .id(dayKey(day))
                            }
                        }

                        Button("Show more days") { daysShown += 30 }
                            .padding(20)
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: model.dayTick) {
                    // Midnight rollover: start again from the new today.
                    firstDay = calendar.startOfDay(for: Date())
                    selectedDay = firstDay
                }
            }
        }
        .navigationTitle("Upcoming")
        .onAppear { model.visibleTaskIDs = visibleOrder }
        .onChange(of: visibleOrder) { _, ids in model.visibleTaskIDs = ids }
        .taskDetailPanel()
    }

    private func dayKey(_ day: Date) -> String {
        KarmaEngine.dayKey(for: day, calendar: calendar)
    }

    // MARK: - Month strip

    private func monthStrip(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<Self.stripDays, id: \.self) { offset in
                    if let day = calendar.date(byAdding: .day, value: offset,
                                               to: calendar.startOfDay(for: Date())) {
                        dayCell(day, proxy)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func dayCell(_ day: Date, _ proxy: ScrollViewProxy) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let count = store.tasksDue(on: day).count
        let weekdayF = DateFormatter()
        weekdayF.dateFormat = "EEE"

        return Button {
            selectedDay = day
            proxy.scrollTo(dayKey(day), anchor: .top)
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
        .dropsTask(onDay: day, store: store)
    }

    // MARK: - Blocks

    /// Overdue first, then each shown day in order — matching the rendered list.
    private var visibleOrder: [UUID] {
        var ids = model.shownOverdue(store.overdueTasks()
            .filter { !calendar.isDateInToday($0.dueDate ?? Date()) })
            .map(\.id)
        for offset in 0..<daysShown {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            ids += store.tasksDue(on: day).map(\.id)
        }
        return ids
    }

    private var overdueBlock: some View {
        OverdueSection(overdue: store.overdueTasks().filter { !calendar.isDateInToday($0.dueDate ?? Date()) },
                       headerColor: .red)
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
                    .draggable(task.id.uuidString)
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
        .dropsTask(onDay: day, store: store)
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
        _ = store.addTask(from: QuickAddParser().parse(trimmed).placed(on: day))
        text = ""
    }
}
