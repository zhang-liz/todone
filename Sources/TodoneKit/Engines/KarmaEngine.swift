import Foundation

/// Pure karma math: points for completions, daily/weekly goal bonuses, streaks.
public enum KarmaEngine {
    public static let completionPoints = 5
    public static let dailyGoalBonus = 10
    public static let weeklyGoalBonus = 25

    /// Day key "yyyy-MM-dd".
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Week key "yyyy-Www" using ISO week numbering.
    public static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Apply a task completion. `completedToday` / `completedThisWeek` are the
    /// counts INCLUDING this completion. Mutates `state` (points, streaks).
    public static func applyCompletion(state: inout KarmaState,
                                       date: Date,
                                       completedToday: Int,
                                       completedThisWeek: Int,
                                       calendar: Calendar = .current) {
        guard state.karmaEnabled, !state.vacationMode else { return }

        state.points += completionPoints

        let day = dayKey(for: date, calendar: calendar)
        let week = weekKey(for: date, calendar: calendar)

        // Daily goal crossing: award once, on the completion that reaches it.
        if completedToday == state.dailyGoal, state.lastDailyStreakDay != day {
            state.points += dailyGoalBonus
            // Streak continues if the previous counted day was yesterday.
            if let last = state.lastDailyStreakDay,
               let lastDate = dateFromDayKey(last, calendar: calendar),
               let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)),
               calendar.isDate(lastDate, inSameDayAs: yesterday) {
                state.currentDailyStreak += 1
            } else {
                state.currentDailyStreak = 1
            }
            state.maxDailyStreak = max(state.maxDailyStreak, state.currentDailyStreak)
            state.lastDailyStreakDay = day
        }

        // Weekly goal crossing.
        if completedThisWeek == state.weeklyGoal, state.lastWeeklyStreakWeek != week {
            state.points += weeklyGoalBonus
            if let last = state.lastWeeklyStreakWeek,
               isConsecutiveWeek(previous: last, current: week, near: date, calendar: calendar) {
                state.currentWeeklyStreak += 1
            } else {
                state.currentWeeklyStreak = 1
            }
            state.maxWeeklyStreak = max(state.maxWeeklyStreak, state.currentWeeklyStreak)
            state.lastWeeklyStreakWeek = week
        }
    }

    /// Break the daily streak if a day passed without meeting the goal.
    /// Call on app launch / day change.
    public static func reconcileStreaks(state: inout KarmaState, now: Date, calendar: Calendar = .current) {
        guard state.karmaEnabled, !state.vacationMode else { return }
        if let last = state.lastDailyStreakDay,
           let lastDate = dateFromDayKey(last, calendar: calendar) {
            let today = calendar.startOfDay(for: now)
            if let daysSince = calendar.dateComponents([.day], from: lastDate, to: today).day,
               daysSince > 1 {
                state.currentDailyStreak = 0
            }
        }
        if let lastWeek = state.lastWeeklyStreakWeek {
            let thisWeek = weekKey(for: now, calendar: calendar)
            if lastWeek != thisWeek,
               let previous = calendar.date(byAdding: .day, value: -7, to: now),
               weekKey(for: previous, calendar: calendar) != lastWeek {
                state.currentWeeklyStreak = 0
            }
        }
    }

    static func dateFromDayKey(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
        return calendar.date(from: comps)
    }

    static func isConsecutiveWeek(previous: String, current: String, near date: Date, calendar: Calendar) -> Bool {
        guard let lastWeekDate = calendar.date(byAdding: .day, value: -7, to: date) else { return false }
        return weekKey(for: lastWeekDate, calendar: calendar) == previous && previous != current
    }
}
