import SwiftUI
import TodoneKit

/// Karma popover: level, points, streaks, last-4-weeks completion chart.
struct KarmaView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let karma = store.karma
        let level = KarmaLevel.level(for: karma.points)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title)
                VStack(alignment: .leading) {
                    Text(level.displayName)
                        .font(.headline)
                    Text("\(karma.points) karma points")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if karma.vacationMode {
                Label("Vacation mode on — streaks frozen", systemImage: "beach.umbrella")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let nextLevel = KarmaLevel(rawValue: level.rawValue + 1) {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(karma.points - level.threshold),
                                 total: Double(nextLevel.threshold - level.threshold))
                    Text("\(nextLevel.threshold - karma.points) points to \(nextLevel.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow {
                    statCell("Today", value: "\(todayCompleted)", goal: "\(karma.dailyGoal)")
                    statCell("This week", value: "\(weekCompleted)", goal: "\(karma.weeklyGoal)")
                }
                GridRow {
                    statCell("Day streak", value: "\(karma.currentDailyStreak)", goal: "best \(karma.maxDailyStreak)")
                    statCell("Week streak", value: "\(karma.currentWeeklyStreak)", goal: "best \(karma.maxWeeklyStreak)")
                }
            }

            Divider()

            Text("Last 4 weeks")
                .font(.headline)
            chart

        }
        .padding(16)
        .frame(width: 320)
    }

    private var todayCompleted: Int {
        store.stat(forDay: KarmaEngine.dayKey(for: Date()))?.completed ?? 0
    }

    private var weekCompleted: Int {
        let week = KarmaEngine.weekKey(for: Date())
        return store.dailyStats
            .filter { stat in
                guard let d = KarmaEngine.dateFromDayKey(stat.day, calendar: Calendar.current) else { return false }
                return KarmaEngine.weekKey(for: d) == week
            }
            .reduce(0) { $0 + $1.completed }
    }

    private func statCell(_ title: String, value: String, goal: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title3.weight(.semibold))
                Text("/ \(goal)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 120, alignment: .leading)
    }

    /// Simple bar chart of daily completions, last 28 days.
    private var chart: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [(String, Int)] = (0..<28).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let key = KarmaEngine.dayKey(for: d, calendar: cal)
            return (key, store.stat(forDay: key)?.completed ?? 0)
        }
        let maxValue = max(days.map(\.1).max() ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(days, id: \.0) { day in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(day.1 >= store.karma.dailyGoal ? Color.green : Color.accentColor.opacity(0.6))
                    .frame(width: 7, height: max(3, CGFloat(day.1) / CGFloat(maxValue) * 60))
                    .help("\(day.0): \(day.1) completed")
            }
        }
        .frame(height: 64, alignment: .bottom)
    }
}
