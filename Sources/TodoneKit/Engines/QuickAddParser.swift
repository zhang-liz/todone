import Foundation

/// A recognized token inside a quick-add input string.
public struct QuickAddToken: Equatable {
    public enum Kind: Equatable {
        case date
        case recurrence
        case priority
        case project
        case section
        case label
    }

    public var kind: Kind
    /// UTF-16 range in the original input.
    public var range: NSRange

    public init(kind: Kind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// The structured result of parsing a quick-add string.
public struct ParsedQuickAdd: Equatable {
    public var title: String
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var recurrence: RecurrenceRule?
    public var priority: Priority
    public var projectName: String?
    public var sectionName: String?
    public var labelNames: [String]
    public var tokens: [QuickAddToken]

    public init(title: String = "", dueDate: Date? = nil, hasDueTime: Bool = false,
                recurrence: RecurrenceRule? = nil, priority: Priority = .p4,
                projectName: String? = nil, sectionName: String? = nil,
                labelNames: [String] = [], tokens: [QuickAddToken] = []) {
        self.title = title
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.recurrence = recurrence
        self.priority = priority
        self.projectName = projectName
        self.sectionName = sectionName
        self.labelNames = labelNames
        self.tokens = tokens
    }
}

/// Parses Todoist-style quick-add syntax:
///   "Pay rent tomorrow 5pm p1 #Finance /Bills @home every month"
/// Tokens: dates & times, `every ...` recurrence, p1–p3, #project (or
/// #"quoted name"), /section, @label. `disabledRanges` lets the UI "un-parse"
/// tokens the user clicked; those ranges are left as plain title text.
public struct QuickAddParser {
    public var calendar: Calendar
    public var now: Date

    public init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(_ input: String, disabledRanges: [NSRange] = []) -> ParsedQuickAdd {
        let ns = input as NSString
        var result = ParsedQuickAdd()
        var claimed: [NSRange] = []

        // Working copy where recognized tokens are blanked out (space-filled,
        // length-preserving) so later passes don't re-match inside them.
        var masked = input

        func blank(_ range: NSRange) {
            let m = masked as NSString
            let replacement = String(repeating: " ", count: range.length)
            masked = m.replacingCharacters(in: NSRange(location: range.location, length: range.length),
                                           with: replacement)
        }

        func isDisabled(_ range: NSRange) -> Bool {
            disabledRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        func claim(_ range: NSRange, _ kind: QuickAddToken.Kind) {
            claimed.append(range)
            result.tokens.append(QuickAddToken(kind: kind, range: range))
            blank(range)
        }

        // 1. Symbol tokens: #project, #"project", /section, @label.
        let symbolPatterns: [(String, QuickAddToken.Kind)] = [
            (##"(?<=^|\s)#"([^"]+)""##, .project),
            (##"(?<=^|\s)#([^\s#/@"]+)"##, .project),
            (##"(?<=^|\s)/"([^"]+)""##, .section),
            (##"(?<=^|\s)/([^\s#/@"]+)"##, .section),
            (##"(?<=^|\s)@([^\s#/@"]+)"##, .label),
        ]
        for (pattern, kind) in symbolPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let m = masked as NSString
            for match in regex.matches(in: masked, range: NSRange(location: 0, length: m.length)) {
                if isDisabled(match.range) { continue }
                let value = m.substring(with: match.range(at: 1))
                switch kind {
                case .project where result.projectName == nil:
                    result.projectName = value
                    claim(match.range, .project)
                case .section where result.sectionName == nil:
                    result.sectionName = value
                    claim(match.range, .section)
                case .label:
                    if !result.labelNames.contains(value) {
                        result.labelNames.append(value)
                    }
                    claim(match.range, .label)
                default:
                    break
                }
            }
        }

        // 2. Priority: p1, p2, p3 (p4 is the default; typing it is a no-op token).
        if let regex = try? NSRegularExpression(pattern: #"(?<=^|\s)[pP]([1-4])(?=\s|$)"#) {
            let m = masked as NSString
            if let match = regex.matches(in: masked, range: NSRange(location: 0, length: m.length))
                .first(where: { !isDisabled($0.range) }) {
                if let n = Int(m.substring(with: match.range(at: 1))), let p = Priority(rawValue: n) {
                    result.priority = p
                    claim(match.range, .priority)
                }
            }
        }

        // 3. Recurrence ("every ..."), before plain dates so weekday lists
        //    aren't eaten by the date parser.
        if let (rule, range) = RecurrenceRule.parse(from: masked), !isDisabled(range) {
            result.recurrence = rule
            claim(range, .recurrence)
        }

        // 4. Date/time.
        let dateParser = NLDateParser(calendar: calendar, now: now)
        if let parsed = dateParser.parse(masked) {
            let usable = parsed.ranges.filter { !isDisabled($0) }
            if usable.count == parsed.ranges.count {
                result.dueDate = parsed.date
                result.hasDueTime = parsed.hasTime
                for r in parsed.ranges { claim(r, .date) }
            }
        }

        // A recurring task with no explicit start date starts today (or at the
        // next matching weekday for weekday rules).
        if result.recurrence != nil, result.dueDate == nil {
            let today = calendar.startOfDay(for: now)
            if let rule = result.recurrence, !rule.weekdays.isEmpty,
               !rule.weekdays.contains(calendar.component(.weekday, from: today)) {
                result.dueDate = rule.nextOccurrence(after: today, calendar: calendar)
            } else {
                result.dueDate = today
            }
        }

        // 5. Title = whatever wasn't claimed.
        let title = removeRanges(claimed, from: ns)
        result.title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        result.tokens.sort { $0.range.location < $1.range.location }
        return result
    }

    private func removeRanges(_ ranges: [NSRange], from ns: NSString) -> String {
        var out = ""
        var idx = 0
        let sorted = ranges.sorted { $0.location < $1.location }
        for r in sorted {
            if r.location > idx {
                out += ns.substring(with: NSRange(location: idx, length: r.location - idx))
            }
            idx = max(idx, r.location + r.length)
        }
        if idx < ns.length {
            out += ns.substring(from: idx)
        }
        return out
    }
}
