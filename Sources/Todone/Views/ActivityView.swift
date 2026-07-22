import SwiftUI
import TodoneKit

/// Global activity log grouped by day.
struct ActivityView: View {
    @Environment(AppStore.self) private var store

    @State private var typeFilter: ActivityType?

    var body: some View {
        List {
            ForEach(groupedEvents, id: \.day) { group in
                Section(group.title) {
                    ForEach(group.events) { event in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: event.type))
                                .foregroundStyle(color(for: event.type))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(eventText(event))
                                if !event.projectName.isEmpty {
                                    Text(event.projectName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(event.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if store.events.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath")
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            Picker("Type", selection: $typeFilter) {
                Text("All events").tag(ActivityType?.none)
                Text("Added").tag(ActivityType?.some(.added))
                Text("Completed").tag(ActivityType?.some(.completed))
                Text("Updated").tag(ActivityType?.some(.updated))
                Text("Deleted").tag(ActivityType?.some(.deleted))
            }
        }
    }

    private struct DayGroup {
        var day: String
        var title: String
        var events: [ActivityEvent]
    }

    private var groupedEvents: [DayGroup] {
        let filtered = store.events
            .filter { typeFilter == nil || $0.type == typeFilter }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(500)

        var groups: [DayGroup] = []
        let cal = Calendar.current
        for event in filtered {
            let key = KarmaEngine.dayKey(for: event.timestamp, calendar: cal)
            if let idx = groups.firstIndex(where: { $0.day == key }) {
                groups[idx].events.append(event)
            } else {
                let title: String
                if cal.isDateInToday(event.timestamp) {
                    title = "Today"
                } else if cal.isDateInYesterday(event.timestamp) {
                    title = "Yesterday"
                } else {
                    let f = DateFormatter()
                    f.dateStyle = .medium
                    title = f.string(from: event.timestamp)
                }
                groups.append(DayGroup(day: key, title: title, events: [event]))
            }
        }
        return groups
    }

    private func icon(for type: ActivityType) -> String {
        switch type {
        case .added: return "plus.circle"
        case .completed: return "checkmark.circle.fill"
        case .uncompleted: return "arrow.uturn.backward.circle"
        case .updated: return "pencil.circle"
        case .deleted: return "trash.circle"
        }
    }

    private func color(for type: ActivityType) -> Color {
        switch type {
        case .added: return .blue
        case .completed: return .green
        case .uncompleted: return .orange
        case .updated: return .secondary
        case .deleted: return .red
        }
    }

    private func eventText(_ event: ActivityEvent) -> String {
        switch event.type {
        case .added: return "Added \"\(event.taskTitle)\""
        case .completed: return "Completed \"\(event.taskTitle)\""
        case .uncompleted: return "Uncompleted \"\(event.taskTitle)\""
        case .updated: return "Updated \"\(event.taskTitle)\""
        case .deleted: return "Deleted \"\(event.taskTitle)\""
        }
    }
}

/// All completed tasks across projects.
struct CompletedView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let completed = store.tasks
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        Group {
            if completed.isEmpty {
                ContentUnavailableView("Nothing completed yet", systemImage: "checkmark.circle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(completed) { task in
                            TaskRowView(task: task, showsProject: true)
                                .padding(.horizontal, 20)
                                .opacity(0.7)
                            Divider().padding(.leading, 48)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Completed")
    }
}
