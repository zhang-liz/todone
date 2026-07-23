import Foundation
import Testing
@testable import TodoneKit

/// Sanity checks at personal-data scale: 5k tasks should stay snappy.
@Suite struct ScaleTests {
    @Test func fiveThousandTasksSaveLoadAndFilter() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10))!

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todone-scale-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("store.json")

        let store = AppStore()
        store.calendar = cal
        store.load(from: url)

        let projects = (0..<20).map { store.addProject(name: "Project \($0)") }
        let labels = (0..<10).map { store.addLabel(name: "label\($0)") }

        for i in 0..<5000 {
            let due = i % 3 == 0
                ? cal.date(byAdding: .day, value: i % 60 - 10, to: cal.startOfDay(for: now))
                : nil
            store.addTask(title: "Task \(i)",
                          priority: Priority(rawValue: (i % 4) + 1)!,
                          dueDate: due,
                          projectID: projects[i % projects.count].id,
                          labelIDs: i % 5 == 0 ? [labels[i % labels.count].id] : [])
        }

        // Save + reload round trip.
        let saveStart = Date()
        store.saveNow()
        let saveTime = Date().timeIntervalSince(saveStart)
        #expect(saveTime < 3.0, "save took \(saveTime)s")

        let reload = AppStore()
        reload.calendar = cal
        let loadStart = Date()
        reload.load(from: url)
        let loadTime = Date().timeIntervalSince(loadStart)
        #expect(loadTime < 3.0, "load took \(loadTime)s")
        #expect(reload.tasks.count == 5000)

        // Filter evaluation over the full set; compare against a brute-force count.
        let expr = try FilterEngine.parse("7 days & !no label", calendar: cal, now: now)
        let filterStart = Date()
        let matches = reload.tasksMatching(expr, now: now)
        let filterTime = Date().timeIntervalSince(filterStart)
        #expect(filterTime < 2.0, "filter took \(filterTime)s")

        let today = cal.startOfDay(for: now)
        let limit = cal.date(byAdding: .day, value: 7, to: today)!
        let expected = reload.incompleteTasks.filter { t in
            guard let due = t.dueDate, !t.labelIDs.isEmpty else { return false }
            let d = cal.startOfDay(for: due)
            return d >= today && d < limit
        }.count
        #expect(matches.count == expected)
        #expect(expected > 0)

        // Today view queries.
        let todayStart = Date()
        _ = reload.tasksDue(on: now)
        _ = reload.overdueTasks(now: now)
        let todayTime = Date().timeIntervalSince(todayStart)
        #expect(todayTime < 1.0, "today queries took \(todayTime)s")

        try? FileManager.default.removeItem(at: dir)
    }
}
