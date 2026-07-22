import Foundation

/// A recurring-due-date rule, parsed from Todoist-style text like
/// "every day", "every 2 weeks", "every mon, fri", "every month on the 15th",
/// "every workday", or the strict variant "every! ..." which advances from the
/// completion date instead of the previous due date.
public struct RecurrenceRule: Equatable {
    public enum Unit: String, Equatable {
        case day, week, month, year
    }

    public var interval: Int
    public var unit: Unit
    /// Calendar weekday numbers (1 = Sunday ... 7 = Saturday). When non-empty
    /// the rule fires on each of these weekdays.
    public var weekdays: [Int]
    /// Day-of-month for "every month on the 15th". Clamped to month length.
    public var monthDay: Int?
    /// Strict ("every!"): next occurrence computed from the completion date.
    public var strict: Bool
    /// Normalized display text, also the serialized form.
    public var displayText: String

    public init(interval: Int = 1, unit: Unit = .day, weekdays: [Int] = [],
                monthDay: Int? = nil, strict: Bool = false, displayText: String = "") {
        self.interval = interval
        self.unit = unit
        self.weekdays = weekdays
        self.monthDay = monthDay
        self.strict = strict
        self.displayText = displayText
    }

    // MARK: - Parsing

    /// Parse a recurrence expression out of `text`. Returns the rule and the
    /// UTF-16 range it occupied, or nil if no recurrence found.
    public static func parse(from text: String) -> (rule: RecurrenceRule, range: NSRange)? {
        let lower = (text as NSString).lowercased as NSString
        let full = NSRange(location: 0, length: lower.length)

        let weekdayAlt = "sun|sunday|mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday"

        // every [!] mon, fri / every tue
        if let regex = try? NSRegularExpression(
            pattern: #"\bevery(!?) ((?:(?:"# + weekdayAlt + #")(?:, ?| and | ))*(?:"# + weekdayAlt + #"))\b"#),
            let m = regex.firstMatch(in: lower as String, range: full) {
            let strict = lower.substring(with: m.range(at: 1)) == "!"
            let listText = lower.substring(with: m.range(at: 2))
            let parts = listText
                .replacingOccurrences(of: " and ", with: ",")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let days = parts.compactMap { NLDateParser.weekdayNames[$0] }
            if !days.isEmpty, days.count == parts.count {
                let names = days.sorted().map { Self.shortName(forWeekday: $0) }
                let rule = RecurrenceRule(interval: 1, unit: .week, weekdays: days.sorted(),
                                          strict: strict,
                                          displayText: "every\(strict ? "!" : "") " + names.joined(separator: ", "))
                return (rule, m.range)
            }
        }

        // every [!] workday / weekday
        if let regex = try? NSRegularExpression(pattern: #"\bevery(!?) (workday|weekday)\b"#),
           let m = regex.firstMatch(in: lower as String, range: full) {
            let strict = lower.substring(with: m.range(at: 1)) == "!"
            let rule = RecurrenceRule(interval: 1, unit: .week, weekdays: [2, 3, 4, 5, 6],
                                      strict: strict,
                                      displayText: "every\(strict ? "!" : "") workday")
            return (rule, m.range)
        }

        // every [!] month on the 15th
        if let regex = try? NSRegularExpression(pattern: #"\bevery(!?) month on the (\d{1,2})(?:st|nd|rd|th)?\b"#),
           let m = regex.firstMatch(in: lower as String, range: full) {
            let strict = lower.substring(with: m.range(at: 1)) == "!"
            if let day = Int(lower.substring(with: m.range(at: 2))), day >= 1, day <= 31 {
                let rule = RecurrenceRule(interval: 1, unit: .month, monthDay: day, strict: strict,
                                          displayText: "every\(strict ? "!" : "") month on the \(day)\(Self.ordinalSuffix(day))")
                return (rule, m.range)
            }
        }

        // every [!] [N] day(s)/week(s)/month(s)/year(s), every morning/evening/night
        if let regex = try? NSRegularExpression(
            pattern: #"\bevery(!?) (?:(\d+)|other )? ?(day|days|week|weeks|month|months|year|years|morning|evening|night)\b"#),
           let m = regex.firstMatch(in: lower as String, range: full) {
            let strict = lower.substring(with: m.range(at: 1)) == "!"
            var interval = 1
            if m.range(at: 2).location != NSNotFound, let n = Int(lower.substring(with: m.range(at: 2))) {
                interval = max(1, n)
            } else if lower.substring(with: m.range).contains("other") {
                interval = 2
            }
            let unitText = lower.substring(with: m.range(at: 3))
            let unit: Unit
            if unitText.hasPrefix("day") || unitText == "morning" || unitText == "evening" || unitText == "night" {
                unit = .day
            } else if unitText.hasPrefix("week") {
                unit = .week
            } else if unitText.hasPrefix("month") {
                unit = .month
            } else {
                unit = .year
            }
            let unitName = unit.rawValue + (interval > 1 ? "s" : "")
            let display = interval > 1
                ? "every\(strict ? "!" : "") \(interval) \(unitName)"
                : "every\(strict ? "!" : "") \(unitName)"
            let rule = RecurrenceRule(interval: interval, unit: unit, strict: strict, displayText: display)
            return (rule, m.range)
        }

        return nil
    }

    /// Deserialize from the stored display text.
    public static func deserialize(_ text: String) -> RecurrenceRule? {
        parse(from: text)?.rule
    }

    // MARK: - Next occurrence

    /// Compute the next due date. `base` is the previous due date for plain
    /// rules, or the completion date for strict ("every!") rules — the caller
    /// picks. Time-of-day of `base` is preserved.
    public func nextOccurrence(after base: Date, calendar: Calendar = .current) -> Date? {
        switch unit {
        case .day:
            return calendar.date(byAdding: .day, value: interval, to: base)
        case .week:
            if weekdays.isEmpty {
                return calendar.date(byAdding: .day, value: 7 * interval, to: base)
            }
            // Next date after base whose weekday is in the set.
            var d = base
            for _ in 0..<15 {
                guard let n = calendar.date(byAdding: .day, value: 1, to: d) else { return nil }
                d = n
                if weekdays.contains(calendar.component(.weekday, from: d)) { return d }
            }
            return nil
        case .month:
            guard let added = calendar.date(byAdding: .month, value: interval, to: base) else { return nil }
            if let day = monthDay {
                var comps = calendar.dateComponents([.year, .month, .hour, .minute], from: added)
                let range = calendar.range(of: .day, in: .month,
                                           for: calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? added)
                comps.day = min(day, range?.count ?? 28)
                return calendar.date(from: comps)
            }
            return added
        case .year:
            return calendar.date(byAdding: .year, value: interval, to: base)
        }
    }

    // MARK: - Helpers

    static func shortName(forWeekday wd: Int) -> String {
        switch wd {
        case 1: return "sun"
        case 2: return "mon"
        case 3: return "tue"
        case 4: return "wed"
        case 5: return "thu"
        case 6: return "fri"
        default: return "sat"
        }
    }

    static func ordinalSuffix(_ n: Int) -> String {
        switch n % 100 {
        case 11, 12, 13: return "th"
        default:
            switch n % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}
