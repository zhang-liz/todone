import Foundation

/// How a task list is ordered on screen.
public enum TaskSort: String, CaseIterable, Codable, Sendable {
    /// The user's drag order. The only option that keeps manual reordering
    /// meaningful, so it stays the default.
    case manual
    case dueDate
    case priority
    case alphabetical
    case dateAdded

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .dueDate: return "Due Date"
        case .priority: return "Priority"
        case .alphabetical: return "Name"
        case .dateAdded: return "Date Added"
        }
    }
}

/// How a task list is split into labelled runs.
public enum TaskGrouping: String, CaseIterable, Codable, Sendable {
    case none
    case priority
    case dueDate
    case project

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .priority: return "Priority"
        case .dueDate: return "Due Date"
        case .project: return "Project"
        }
    }
}

/// A labelled run of tasks produced by grouping.
public struct TaskGroup: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let tasks: [TodoTask]

    public init(id: String, title: String, tasks: [TodoTask]) {
        self.id = id
        self.title = title
        self.tasks = tasks
    }

    public static func == (lhs: TaskGroup, rhs: TaskGroup) -> Bool {
        lhs.id == rhs.id && lhs.tasks.map(\.id) == rhs.tasks.map(\.id)
    }
}

public enum TaskSorter {

    /// Sort `tasks` by `sort`.
    ///
    /// Every comparison falls back to `sortOrder`, so equal keys keep the
    /// user's manual arrangement instead of shuffling between renders.
    public static func sorted(_ tasks: [TodoTask], by sort: TaskSort) -> [TodoTask] {
        switch sort {
        case .manual:
            return tasks.sorted { $0.sortOrder < $1.sortOrder }
        case .dueDate:
            // Undated tasks sink to the bottom rather than sorting as 1970.
            return tasks.sorted {
                let l = $0.dueDate ?? .distantFuture
                let r = $1.dueDate ?? .distantFuture
                if l != r { return l < r }
                return $0.sortOrder < $1.sortOrder
            }
        case .priority:
            return tasks.sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.sortOrder < $1.sortOrder
            }
        case .alphabetical:
            return tasks.sorted {
                let c = $0.title.localizedCaseInsensitiveCompare($1.title)
                if c != .orderedSame { return c == .orderedAscending }
                return $0.sortOrder < $1.sortOrder
            }
        case .dateAdded:
            return tasks.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.sortOrder < $1.sortOrder
            }
        }
    }

    /// Split `tasks` into labelled groups, preserving the order within each.
    /// Returns a single untitled group when grouping is off.
    public static func grouped(_ tasks: [TodoTask], by grouping: TaskGrouping,
                               calendar: Calendar = .current, now: Date = Date(),
                               projectName: (UUID) -> String? = { _ in nil }) -> [TaskGroup] {
        switch grouping {
        case .none:
            return [TaskGroup(id: "all", title: "", tasks: tasks)]

        case .priority:
            return Priority.allCases.compactMap { p in
                let hits = tasks.filter { $0.priority == p }
                guard !hits.isEmpty else { return nil }
                return TaskGroup(id: "p\(p.rawValue)", title: p.displayName, tasks: hits)
            }

        case .dueDate:
            let today = calendar.startOfDay(for: now)
            var overdue: [TodoTask] = []
            var todayTasks: [TodoTask] = []
            var upcoming: [TodoTask] = []
            var undated: [TodoTask] = []
            for t in tasks {
                guard let due = t.dueDate else { undated.append(t); continue }
                let day = calendar.startOfDay(for: due)
                if day < today { overdue.append(t) }
                else if day == today { todayTasks.append(t) }
                else { upcoming.append(t) }
            }
            return [
                TaskGroup(id: "overdue", title: "Overdue", tasks: overdue),
                TaskGroup(id: "today", title: "Today", tasks: todayTasks),
                TaskGroup(id: "upcoming", title: "Upcoming", tasks: upcoming),
                TaskGroup(id: "undated", title: "No Date", tasks: undated),
            ].filter { !$0.tasks.isEmpty }

        case .project:
            var order: [UUID] = []
            var buckets: [UUID: [TodoTask]] = [:]
            for t in tasks {
                if buckets[t.projectID] == nil { order.append(t.projectID) }
                buckets[t.projectID, default: []].append(t)
            }
            return order.map { id in
                TaskGroup(id: id.uuidString,
                          title: projectName(id) ?? "Project",
                          tasks: buckets[id] ?? [])
            }
        }
    }
}
