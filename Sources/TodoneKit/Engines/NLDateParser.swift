import Foundation

/// Result of natural-language date recognition inside a string.
public struct ParsedNLDate: Equatable {
    public var date: Date
    public var hasTime: Bool
    /// Ranges (UTF-16 offsets into the source string) that the date/time expressions occupied.
    public var ranges: [NSRange]

    public init(date: Date, hasTime: Bool, ranges: [NSRange]) {
        self.date = date
        self.hasTime = hasTime
        self.ranges = ranges
    }
}

/// Parses natural-language date expressions like "tomorrow", "next monday",
/// "jul 30", "in 3 days", "3pm". Finds the expression anywhere in the input.
public struct NLDateParser {
    public var calendar: Calendar
    public var now: Date

    public init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10,
        "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    // Calendar weekday numbers: 1 = Sunday ... 7 = Saturday
    static let weekdayNames: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    /// Parse a date expression from `text`. Returns nil if none found.
    public func parse(_ text: String) -> ParsedNLDate? {
        let ns = text as NSString
        let lower = ns.lowercased as NSString

        var dayDate: Date?
        var dayRange: NSRange?

        // Try day-level patterns in priority order (longer/more specific first).
        let dayPatterns: [(String, (NSTextCheckingResult, NSString) -> Date?)] = [
            // in N days/weeks/months/years
            (#"\bin (\d+) (day|days|week|weeks|month|months|year|years)\b"#, { m, s in
                guard let n = Int(s.substring(with: m.range(at: 1))) else { return nil }
                let unit = s.substring(with: m.range(at: 2))
                var comps = DateComponents()
                if unit.hasPrefix("day") { comps.day = n }
                else if unit.hasPrefix("week") { comps.day = n * 7 }
                else if unit.hasPrefix("month") { comps.month = n }
                else { comps.year = n }
                return self.calendar.date(byAdding: comps, to: self.startOfToday)
            }),
            // month-name day [, year]  e.g. "jul 30", "july 30 2027"
            (#"\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\.? (\d{1,2})(?:st|nd|rd|th)?(?:,? (\d{4}))?\b"#, { m, s in
                guard let month = Self.monthNames[s.substring(with: m.range(at: 1))],
                      let day = Int(s.substring(with: m.range(at: 2))) else { return nil }
                let year = m.range(at: 3).location != NSNotFound ? Int(s.substring(with: m.range(at: 3))) : nil
                return self.dateFor(month: month, day: day, year: year)
            }),
            // day month-name [year]  e.g. "30 jul"
            (#"\b(\d{1,2})(?:st|nd|rd|th)? (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\.?(?: (\d{4}))?\b"#, { m, s in
                guard let day = Int(s.substring(with: m.range(at: 1))),
                      let month = Self.monthNames[s.substring(with: m.range(at: 2))] else { return nil }
                let year = m.range(at: 3).location != NSNotFound ? Int(s.substring(with: m.range(at: 3))) : nil
                return self.dateFor(month: month, day: day, year: year)
            }),
            // numeric M/D or M/D/YYYY
            (#"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#, { m, s in
                guard let month = Int(s.substring(with: m.range(at: 1))),
                      let day = Int(s.substring(with: m.range(at: 2))),
                      month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
                var year: Int? = nil
                if m.range(at: 3).location != NSNotFound, var y = Int(s.substring(with: m.range(at: 3))) {
                    if y < 100 { y += 2000 }
                    year = y
                }
                return self.dateFor(month: month, day: day, year: year)
            }),
            // next weekday
            (#"\bnext (sun|sunday|mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday)\b"#, { m, s in
                guard let wd = Self.weekdayNames[s.substring(with: m.range(at: 1))] else { return nil }
                return self.next(weekday: wd, after: self.startOfToday)
            }),
            // next week / next month / next year
            (#"\bnext week\b"#, { _, _ in
                self.next(weekday: 2, after: self.startOfToday) // next Monday
            }),
            (#"\bnext month\b"#, { _, _ in
                self.calendar.date(byAdding: .month, value: 1, to: self.startOfToday)
            }),
            (#"\bnext year\b"#, { _, _ in
                self.calendar.date(byAdding: .year, value: 1, to: self.startOfToday)
            }),
            // today / tomorrow / yesterday shortcuts
            (#"\b(today|tod)\b"#, { _, _ in self.startOfToday }),
            (#"\b(tomorrow|tmrw|tom)\b"#, { _, _ in
                self.calendar.date(byAdding: .day, value: 1, to: self.startOfToday)
            }),
            (#"\byesterday\b"#, { _, _ in
                self.calendar.date(byAdding: .day, value: -1, to: self.startOfToday)
            }),
            (#"\btonight\b"#, { _, _ in self.startOfToday }),
            // bare weekday
            (#"\b(sun|sunday|mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday)\b"#, { m, s in
                guard let wd = Self.weekdayNames[s.substring(with: m.range(at: 1))] else { return nil }
                return self.next(weekday: wd, after: self.startOfToday)
            }),
        ]

        for (pattern, builder) in dayPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: lower as String, range: NSRange(location: 0, length: lower.length))
            for m in matches {
                if let d = builder(m, lower) {
                    dayDate = d
                    dayRange = m.range
                    break
                }
            }
            if dayDate != nil { break }
        }

        // Time patterns: "at 3pm", "3:30pm", "15:00", "at 15"
        var timeComps: DateComponents?
        var timeRange: NSRange?
        let timePatterns: [(String, (NSTextCheckingResult, NSString) -> DateComponents?)] = [
            (#"\b(?:at )?(\d{1,2}):(\d{2}) ?(am|pm)?\b"#, { m, s in
                guard let h = Int(s.substring(with: m.range(at: 1))),
                      let min = Int(s.substring(with: m.range(at: 2))),
                      h <= 23, min <= 59 else { return nil }
                var hour = h
                if m.range(at: 3).location != NSNotFound {
                    let ap = s.substring(with: m.range(at: 3))
                    guard h >= 1, h <= 12 else { return nil }
                    if ap == "pm", h != 12 { hour = h + 12 }
                    if ap == "am", h == 12 { hour = 0 }
                }
                var c = DateComponents(); c.hour = hour; c.minute = min
                return c
            }),
            (#"\b(?:at )?(\d{1,2}) ?(am|pm)\b"#, { m, s in
                guard let h = Int(s.substring(with: m.range(at: 1))), h >= 1, h <= 12 else { return nil }
                let ap = s.substring(with: m.range(at: 2))
                var hour = h
                if ap == "pm", h != 12 { hour = h + 12 }
                if ap == "am", h == 12 { hour = 0 }
                var c = DateComponents(); c.hour = hour; c.minute = 0
                return c
            }),
            (#"\bat (\d{1,2})\b"#, { m, s in
                guard let h = Int(s.substring(with: m.range(at: 1))), h <= 23 else { return nil }
                var c = DateComponents(); c.hour = h; c.minute = 0
                return c
            }),
        ]

        for (pattern, builder) in timePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: lower as String, range: NSRange(location: 0, length: lower.length))
            for m in matches {
                // Skip if this time match overlaps the day-date match (e.g. "7/30").
                if let dr = dayRange, NSIntersectionRange(dr, m.range).length > 0 { continue }
                if let c = builder(m, lower) {
                    timeComps = c
                    timeRange = m.range
                    break
                }
            }
            if timeComps != nil { break }
        }

        // "tonight" implies 8 PM if no explicit time.
        if let dr = dayRange, lower.substring(with: dr) == "tonight", timeComps == nil {
            var c = DateComponents(); c.hour = 20; c.minute = 0
            timeComps = c
            timeRange = nil
        }

        switch (dayDate, timeComps) {
        case (nil, nil):
            return nil
        case (let d?, nil):
            var ranges: [NSRange] = []
            if let r = dayRange { ranges.append(r) }
            return ParsedNLDate(date: d, hasTime: false, ranges: ranges)
        case (let d?, let t?):
            var comps = calendar.dateComponents([.year, .month, .day], from: d)
            comps.hour = t.hour; comps.minute = t.minute
            guard let combined = calendar.date(from: comps) else { return nil }
            var ranges: [NSRange] = []
            if let r = dayRange { ranges.append(r) }
            if let r = timeRange { ranges.append(r) }
            return ParsedNLDate(date: combined, hasTime: true, ranges: ranges)
        case (nil, let t?):
            // Time only: today if still in the future, otherwise tomorrow.
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = t.hour; comps.minute = t.minute
            guard var candidate = calendar.date(from: comps) else { return nil }
            if candidate <= now {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            var ranges: [NSRange] = []
            if let r = timeRange { ranges.append(r) }
            return ParsedNLDate(date: candidate, hasTime: true, ranges: ranges)
        }
    }

    // MARK: - Helpers

    var startOfToday: Date { calendar.startOfDay(for: now) }

    /// Next date strictly after `date` that falls on `weekday` (1 = Sunday).
    func next(weekday: Int, after date: Date) -> Date? {
        var d = date
        for _ in 0..<8 {
            guard let n = calendar.date(byAdding: .day, value: 1, to: d) else { return nil }
            d = n
            if calendar.component(.weekday, from: d) == weekday { return d }
        }
        return nil
    }

    /// Date for month/day; picks this year if the date is today or later, else next year.
    /// An explicit year overrides.
    func dateFor(month: Int, day: Int, year: Int?) -> Date? {
        var comps = DateComponents()
        comps.month = month
        comps.day = day
        if let y = year {
            comps.year = y
            return calendar.date(from: comps)
        }
        let currentYear = calendar.component(.year, from: now)
        comps.year = currentYear
        guard let candidate = calendar.date(from: comps) else { return nil }
        if candidate < startOfToday {
            comps.year = currentYear + 1
            return calendar.date(from: comps)
        }
        return candidate
    }
}
