import Foundation
import Testing
@testable import TodoneKit

@Suite struct AllDayTimeZoneTests {
    func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    func july22(_ cal: Calendar, hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: hour))!
    }

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("todone.json")
    }

    func store(_ cal: Calendar, at url: URL) -> AppStore {
        let s = AppStore()
        s.calendar = cal
        s.load(from: url)
        return s
    }

    // An all-day task moved to the day before after travel to a zone further west.
    @Test func allDayTaskKeepsItsDayWhenLoadedInAnotherZone() throws {
        let tokyo = calendar("Asia/Tokyo")
        let losAngeles = calendar("America/Los_Angeles")
        let url = tempURL()
        let first = store(tokyo, at: url)
        let moment = july22(tokyo, hour: 15)
        first.addTask(title: "all day", dueDate: july22(tokyo))
        first.addTask(title: "timed", dueDate: moment, hasDueTime: true)
        first.saveNow()

        let second = store(losAngeles, at: url)
        let allDay = try #require(second.tasks.first { $0.title == "all day" })
        let timed = try #require(second.tasks.first { $0.title == "timed" })
        #expect(allDay.dueDate == july22(losAngeles))
        #expect(timed.dueDate == moment)

        // Saved and loaded again in the same zone, the date stays where it is.
        second.saveNow()
        let third = store(losAngeles, at: url)
        #expect(third.tasks.first { $0.title == "all day" }?.dueDate == july22(losAngeles))

        // Back home, it is still the same day.
        let fourth = store(tokyo, at: url)
        #expect(fourth.tasks.first { $0.title == "all day" }?.dueDate == july22(tokyo))
    }

    @Test func fileWithNoZoneIsLeftAsItIs() throws {
        let losAngeles = calendar("America/Los_Angeles")
        let url = tempURL()
        let first = store(losAngeles, at: url)
        first.addTask(title: "all day", dueDate: july22(losAngeles))
        first.saveNow()

        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(json["timeZoneID"] as? String == "America/Los_Angeles")
        json["timeZoneID"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let second = store(calendar("Asia/Tokyo"), at: url)
        #expect(second.tasks.first?.dueDate == july22(losAngeles))
    }

    @Test func allDayTaskKeepsItsDayWhenTheZoneChangesWhileRunning() {
        let tokyo = calendar("Asia/Tokyo")
        let losAngeles = calendar("America/Los_Angeles")
        let s = AppStore()
        s.calendar = tokyo
        let moment = july22(tokyo, hour: 15)
        let allDay = s.addTask(title: "all day", dueDate: july22(tokyo))
        let timed = s.addTask(title: "timed", dueDate: moment, hasDueTime: true)

        s.timeZoneDidChange(to: losAngeles.timeZone)

        #expect(allDay.dueDate == july22(losAngeles))
        #expect(timed.dueDate == moment)
        #expect(s.tasksDue(on: july22(losAngeles)).map(\.id) == [allDay.id])
    }

    @Test func undoAfterAZoneChangeKeepsTheDay() {
        let tokyo = calendar("Asia/Tokyo")
        let losAngeles = calendar("America/Los_Angeles")
        let s = AppStore()
        s.calendar = tokyo
        let allDay = s.addTask(title: "all day", dueDate: july22(tokyo))
        s.updateTask(allDay) { $0.title = "renamed" }

        s.timeZoneDidChange(to: losAngeles.timeZone)
        s.undo()

        #expect(s.task(allDay.id)?.title == "all day")
        #expect(s.task(allDay.id)?.dueDate == july22(losAngeles))
    }
}
