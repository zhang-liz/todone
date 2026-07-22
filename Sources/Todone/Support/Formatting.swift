import SwiftUI
import TodoneKit

enum DueDateFormatter {
    /// Todoist-style short due-date text: Today, Tomorrow, weekday within a
    /// week, else "Jul 30" (with year when not this year). Appends time.
    static func text(for task: TodoTask, calendar: Calendar = .current, now: Date = Date()) -> String? {
        guard let due = task.dueDate else { return nil }
        var text = dayText(for: due, calendar: calendar, now: now)
        if task.hasDueTime {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            text += " " + f.string(from: due)
        }
        return text
    }

    static func dayText(for due: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        let diff = calendar.dateComponents([.day], from: today, to: day).day ?? 0

        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: due)
        default:
            let f = DateFormatter()
            let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
            f.dateFormat = sameYear ? "MMM d" : "MMM d yyyy"
            return f.string(from: due)
        }
    }

    static func color(for task: TodoTask, calendar: Calendar = .current, now: Date = Date()) -> Color {
        guard let due = task.dueDate else { return .secondary }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        let diff = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if diff < 0 || (task.hasDueTime && due < now) { return Color(hex: "#D1453B") }
        switch diff {
        case 0: return Color(hex: "#058527")
        case 1: return Color(hex: "#AD6200")
        case 2...6: return Color(hex: "#692FC2")
        default: return .secondary
        }
    }
}
