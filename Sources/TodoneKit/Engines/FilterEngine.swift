import Foundation

/// ASCII character → UTF-16 code unit, for NSString scanning.
@inline(__always) private func u(_ c: Unicode.Scalar) -> unichar { unichar(c.value) }

// MARK: - AST

public indirect enum FilterExpr: Equatable {
    case and(FilterExpr, FilterExpr)
    case or(FilterExpr, FilterExpr)
    case not(FilterExpr)
    case term(FilterTerm)
}

public enum FilterTerm: Equatable {
    case all                      // "all" / "view all"
    case today
    case tomorrow
    case overdue
    case noDate
    case noTime
    case recurring
    case subtask
    case priority(Priority)
    case noPriority               // alias of p4
    case project(String, includeSubprojects: Bool)
    case section(String)
    case label(String)
    case noLabel
    case nextNDays(Int)
    case dateOn(Date)
    case dateBefore(Date)
    case dateAfter(Date)
    case createdBefore(Date)
    case createdAfter(Date)
    case search(String)
}

public struct FilterParseError: Error, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

// MARK: - Context

/// Everything the evaluator needs to know about the world besides the task itself.
public struct FilterContext {
    public var calendar: Calendar
    public var now: Date
    public var projectName: (UUID) -> String?
    public var sectionName: (UUID) -> String?
    public var labelNames: (TodoTask) -> [String]
    /// Project IDs matching a name, including descendants when asked.
    public var projectIDs: (String, _ includeSubprojects: Bool) -> Set<UUID>

    public init(calendar: Calendar = .current, now: Date = Date(),
                projectName: @escaping (UUID) -> String?,
                sectionName: @escaping (UUID) -> String?,
                labelNames: @escaping (TodoTask) -> [String],
                projectIDs: @escaping (String, Bool) -> Set<UUID>) {
        self.calendar = calendar
        self.now = now
        self.projectName = projectName
        self.sectionName = sectionName
        self.labelNames = labelNames
        self.projectIDs = projectIDs
    }
}

// MARK: - Engine

/// Parses and evaluates Todoist-style filter queries, e.g.
/// "today & p1", "#Work | @waiting", "7 days & !subtask", "date before: jul 30".
public enum FilterEngine {

    public static func parse(_ query: String, calendar: Calendar = .current, now: Date = Date()) throws -> FilterExpr {
        var parser = Parser(query, calendar: calendar, now: now)
        let expr = try parser.parseExpression()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw FilterParseError("Unexpected text: \"\(parser.remainingText())\"")
        }
        return expr
    }

    /// Evaluate against a single (incomplete) task.
    public static func evaluate(_ expr: FilterExpr, task: TodoTask, context: FilterContext) -> Bool {
        switch expr {
        case .and(let l, let r):
            return evaluate(l, task: task, context: context) && evaluate(r, task: task, context: context)
        case .or(let l, let r):
            return evaluate(l, task: task, context: context) || evaluate(r, task: task, context: context)
        case .not(let e):
            return !evaluate(e, task: task, context: context)
        case .term(let t):
            return evaluateTerm(t, task: task, context: context)
        }
    }

    static func evaluateTerm(_ term: FilterTerm, task: TodoTask, context: FilterContext) -> Bool {
        let cal = context.calendar
        let today = cal.startOfDay(for: context.now)

        func dueDay() -> Date? {
            guard let due = task.dueDate else { return nil }
            return cal.startOfDay(for: due)
        }

        switch term {
        case .all:
            return true
        case .today:
            return dueDay() == today
        case .tomorrow:
            return dueDay() == cal.date(byAdding: .day, value: 1, to: today)
        case .overdue:
            guard let due = task.dueDate else { return false }
            if task.hasDueTime { return due < context.now }
            return cal.startOfDay(for: due) < today
        case .noDate:
            return task.dueDate == nil
        case .noTime:
            return task.dueDate != nil && !task.hasDueTime
        case .recurring:
            return task.recurrence != nil
        case .subtask:
            return task.parentID != nil
        case .priority(let p):
            return task.priority == p
        case .noPriority:
            return task.priority == .p4
        case .project(let name, let includeSub):
            let ids = context.projectIDs(name, includeSub)
            return ids.contains(task.projectID)
        case .section(let name):
            guard let sid = task.sectionID, let actual = context.sectionName(sid) else { return false }
            return actual.caseInsensitiveCompare(name) == .orderedSame
        case .label(let name):
            return context.labelNames(task).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        case .noLabel:
            return task.labelIDs.isEmpty
        case .nextNDays(let n):
            guard let day = dueDay(),
                  let limit = cal.date(byAdding: .day, value: n, to: today) else { return false }
            return day >= today && day < limit
        case .dateOn(let d):
            return dueDay() == cal.startOfDay(for: d)
        case .dateBefore(let d):
            guard let day = dueDay() else { return false }
            return day < cal.startOfDay(for: d)
        case .dateAfter(let d):
            guard let day = dueDay() else { return false }
            return day > cal.startOfDay(for: d)
        case .createdBefore(let d):
            return task.createdAt < cal.startOfDay(for: d)
        case .createdAfter(let d):
            return task.createdAt > cal.startOfDay(for: d)
        case .search(let text):
            let needle = text.lowercased()
            return task.title.lowercased().contains(needle)
                || task.details.lowercased().contains(needle)
        }
    }

    // MARK: - Parser

    struct Parser {
        let scanner: NSString
        var pos: Int = 0
        let calendar: Calendar
        let now: Date

        init(_ text: String, calendar: Calendar, now: Date) {
            self.scanner = text as NSString
            self.calendar = calendar
            self.now = now
        }

        var isAtEnd: Bool { pos >= scanner.length }

        func remainingText() -> String {
            scanner.substring(from: min(pos, scanner.length)).trimmingCharacters(in: .whitespaces)
        }

        mutating func skipWhitespace() {
            while pos < scanner.length,
                  let scalar = Unicode.Scalar(scanner.character(at: pos)),
                  CharacterSet.whitespaces.contains(scalar) {
                pos += 1
            }
        }

        mutating func peek() -> unichar? {
            skipWhitespace()
            guard pos < scanner.length else { return nil }
            return scanner.character(at: pos)
        }

        // expr := and ("|" and)*
        mutating func parseExpression() throws -> FilterExpr {
            var left = try parseAnd()
            while let c = peek(), c == u("|") {
                pos += 1
                let right = try parseAnd()
                left = .or(left, right)
            }
            return left
        }

        // and := unary ("&" unary)*
        mutating func parseAnd() throws -> FilterExpr {
            var left = try parseUnary()
            while let c = peek(), c == u("&") {
                pos += 1
                let right = try parseUnary()
                left = .and(left, right)
            }
            return left
        }

        // unary := "!" unary | "(" expr ")" | term
        mutating func parseUnary() throws -> FilterExpr {
            guard let c = peek() else { throw FilterParseError("Expected expression") }
            if c == u("!") {
                pos += 1
                return .not(try parseUnary())
            }
            if c == u("(") {
                pos += 1
                let inner = try parseExpression()
                guard let close = peek(), close == u(")") else {
                    throw FilterParseError("Missing closing parenthesis")
                }
                pos += 1
                return inner
            }
            return .term(try parseTerm())
        }

        /// Consume a lowercase keyword (with any internal spaces normalized) if present.
        mutating func consume(_ keyword: String) -> Bool {
            skipWhitespace()
            let rest = scanner.substring(from: pos)
            if rest.lowercased().hasPrefix(keyword.lowercased()) {
                pos += (keyword as NSString).length
                return true
            }
            return false
        }

        /// Read an identifier: quoted string or run of non-delimiter characters.
        mutating func readName() throws -> String {
            skipWhitespace()
            guard pos < scanner.length else { throw FilterParseError("Expected a name") }
            if scanner.character(at: pos) == u("\"") {
                pos += 1
                var out = ""
                while pos < scanner.length, scanner.character(at: pos) != u("\"") {
                    out += scanner.substring(with: NSRange(location: pos, length: 1))
                    pos += 1
                }
                guard pos < scanner.length else { throw FilterParseError("Unterminated quote") }
                pos += 1
                return out
            }
            var out = ""
            let delimiters: Set<unichar> = [u("&"), u("|"),
                                            u("("), u(")"),
                                            u(" ")]
            while pos < scanner.length, !delimiters.contains(scanner.character(at: pos)) {
                out += scanner.substring(with: NSRange(location: pos, length: 1))
                pos += 1
            }
            guard !out.isEmpty else { throw FilterParseError("Expected a name") }
            return out
        }

        /// Read text up to the next top-level delimiter (& | ( )) — for date args.
        mutating func readArgument() throws -> String {
            skipWhitespace()
            var out = ""
            let delimiters: Set<unichar> = [u("&"), u("|"),
                                            u("("), u(")")]
            while pos < scanner.length, !delimiters.contains(scanner.character(at: pos)) {
                out += scanner.substring(with: NSRange(location: pos, length: 1))
                pos += 1
            }
            let trimmed = out.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw FilterParseError("Expected a value") }
            return trimmed
        }

        mutating func parseDateArgument() throws -> Date {
            let text = try readArgument()
            let parser = NLDateParser(calendar: calendar, now: now)
            guard let parsed = parser.parse(text) else {
                throw FilterParseError("Can't understand date \"\(text)\"")
            }
            return parsed.date
        }

        mutating func parseTerm() throws -> FilterTerm {
            skipWhitespace()

            if consume("view all") || consume("all") { return .all }
            if consume("today") || consume("tod") { return .today }
            if consume("tomorrow") || consume("tom") { return .tomorrow }
            if consume("overdue") || consume("od") { return .overdue }
            if consume("no date") || consume("no due date") { return .noDate }
            if consume("no time") { return .noTime }
            if consume("no priority") { return .noPriority }
            if consume("no label") || consume("no labels") { return .noLabel }
            if consume("recurring") { return .recurring }
            if consume("subtask") { return .subtask }

            if consume("date before:") { return .dateBefore(try parseDateArgument()) }
            if consume("date after:") { return .dateAfter(try parseDateArgument()) }
            if consume("date:") { return .dateOn(try parseDateArgument()) }
            if consume("due before:") { return .dateBefore(try parseDateArgument()) }
            if consume("due after:") { return .dateAfter(try parseDateArgument()) }
            if consume("due:") { return .dateOn(try parseDateArgument()) }
            if consume("created before:") { return .createdBefore(try parseDateArgument()) }
            if consume("created after:") { return .createdAfter(try parseDateArgument()) }
            if consume("search:") { return .search(try readArgument()) }

            // N days
            do {
                let saved = pos
                skipWhitespace()
                let rest = scanner.substring(from: pos)
                if let regex = try? NSRegularExpression(pattern: #"^(\d+) days?\b"#),
                   let m = regex.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)),
                   let n = Int((rest as NSString).substring(with: m.range(at: 1))) {
                    pos += m.range.length
                    return .nextNDays(n)
                }
                pos = saved
            }

            // Priorities p1..p4
            do {
                let saved = pos
                skipWhitespace()
                let rest = scanner.substring(from: pos)
                if let regex = try? NSRegularExpression(pattern: #"^[pP]([1-4])\b"#),
                   let m = regex.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)),
                   let n = Int((rest as NSString).substring(with: m.range(at: 1))),
                   let p = Priority(rawValue: n) {
                    pos += m.range.length
                    return .priority(p)
                }
                pos = saved
            }

            guard let c = peek() else { throw FilterParseError("Expected a filter term") }

            if c == u("#") {
                pos += 1
                var includeSub = false
                if pos < scanner.length, scanner.character(at: pos) == u("#") {
                    includeSub = true
                    pos += 1
                }
                return .project(try readName(), includeSubprojects: includeSub)
            }
            if c == u("/") {
                pos += 1
                return .section(try readName())
            }
            if c == u("@") {
                pos += 1
                return .label(try readName())
            }

            throw FilterParseError("Can't understand \"\(remainingText())\"")
        }
    }
}
