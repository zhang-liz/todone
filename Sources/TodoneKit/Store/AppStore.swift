import Foundation
import Observation

/// Snapshot of the whole object graph — the on-disk JSON document.
public struct StoreDocument: Codable {
    public var version: Int
    public var projects: [Project]
    public var sections: [ProjectSection]
    public var tasks: [TodoTask]
    public var labels: [TaskLabel]
    public var filters: [SavedFilter]
    public var reminders: [TaskReminder]
    public var events: [ActivityEvent]
    public var dailyStats: [DailyStat]
    public var karma: KarmaState

    public init(version: Int = 1, projects: [Project] = [], sections: [ProjectSection] = [],
                tasks: [TodoTask] = [], labels: [TaskLabel] = [], filters: [SavedFilter] = [],
                reminders: [TaskReminder] = [], events: [ActivityEvent] = [],
                dailyStats: [DailyStat] = [], karma: KarmaState = KarmaState()) {
        self.version = version
        self.projects = projects
        self.sections = sections
        self.tasks = tasks
        self.labels = labels
        self.filters = filters
        self.reminders = reminders
        self.events = events
        self.dailyStats = dailyStats
        self.karma = karma
    }
}

/// The application's single source of truth: an observable in-memory object
/// graph persisted as one JSON document with atomic, debounced writes.
@Observable
public final class AppStore {
    public private(set) var projects: [Project] = []
    public private(set) var sections: [ProjectSection] = []
    public private(set) var tasks: [TodoTask] = []
    public private(set) var labels: [TaskLabel] = []
    public private(set) var filters: [SavedFilter] = []
    public private(set) var reminders: [TaskReminder] = []
    public private(set) var events: [ActivityEvent] = []
    public private(set) var dailyStats: [DailyStat] = []
    public var karma = KarmaState() { didSet { scheduleSave() } }

    /// Most recent persistence error, surfaced non-blockingly in the UI.
    public var lastSaveError: String?

    public var calendar = Calendar.current

    /// Called after mutations that affect reminders/badges (wired to the
    /// notification scheduler by the app layer).
    public var onRemindersChanged: (() -> Void)?

    @ObservationIgnored private var storeURL: URL?
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "com.lzhang.todone.save", qos: .utility)
    @ObservationIgnored public var saveDebounce: TimeInterval = 0.5

    // MARK: - Init & persistence

    public init() {}

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Todone/todone.json")
    }

    /// Load from disk (or start fresh) and ensure invariants like the Inbox exist.
    public func load(from url: URL) {
        storeURL = url
        if let data = try? Data(contentsOf: url) {
            if let doc = try? Self.decoder.decode(StoreDocument.self, from: data) {
                projects = doc.projects
                sections = doc.sections
                tasks = doc.tasks
                labels = doc.labels
                filters = doc.filters
                reminders = doc.reminders
                events = doc.events
                dailyStats = doc.dailyStats
                karma = doc.karma
            } else {
                // Unreadable store: keep the bytes aside instead of silently
                // overwriting the user's data on the next save.
                let backup = url.deletingPathExtension()
                    .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? data.write(to: backup)
                lastSaveError = "Store file was unreadable — saved a copy as \(backup.lastPathComponent) and started fresh."
            }
        }
        ensureInbox()
        KarmaEngine.reconcileStreaks(state: &karma, now: Date(), calendar: calendar)
    }

    @discardableResult
    public func ensureInbox() -> Project {
        if let inbox = projects.first(where: { $0.isInbox }) { return inbox }
        let inbox = Project(name: "Inbox", color: .charcoal, isInbox: true, sortOrder: -1)
        projects.append(inbox)
        return inbox
    }

    public var inbox: Project { ensureInbox() }

    func document() -> StoreDocument {
        StoreDocument(projects: projects, sections: sections, tasks: tasks, labels: labels,
                      filters: filters, reminders: reminders, events: events,
                      dailyStats: dailyStats, karma: karma)
    }

    /// ISO8601 with fractional seconds so completion timestamps within the
    /// same second keep their order across a save/load round trip.
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFallback = ISO8601DateFormatter()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoFormatter.string(from: date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = isoFormatter.date(from: s) ?? isoFallback.date(from: s) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad date: \(s)"))
        }
        return d
    }()

    /// Debounce a save. Must be called from the thread that mutates the store
    /// (the main thread in the app); the eventual encode also happens there so
    /// the object graph is never read while another thread mutates it.
    public func scheduleSave() {
        guard storeURL != nil else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.saveNow() }
        }
        saveWorkItem = item
        saveQueue.asyncAfter(deadline: .now() + saveDebounce, execute: item)
    }

    /// Encode and write synchronously on the calling thread. Safe because all
    /// mutations and saves happen on the same (main) thread; write is atomic.
    public func saveNow() {
        guard let url = storeURL else { return }
        do {
            let data = try Self.encoder.encode(document())
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// JSON export of everything (Settings → Data → Export).
    public func exportJSON() throws -> Data {
        var e = Self.encoder
        e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try e.encode(document())
    }

    public func eraseAll() {
        projects = []
        sections = []
        tasks = []
        labels = []
        filters = []
        reminders = []
        events = []
        dailyStats = []
        karma = KarmaState()
        ensureInbox()
        // An erase must hit disk immediately — a debounced save could die with
        // the process and resurrect "erased" data.
        saveNow()
        onRemindersChanged?()
    }

    // MARK: - Lookups

    public func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }
    public func section(_ id: UUID) -> ProjectSection? { sections.first { $0.id == id } }
    public func task(_ id: UUID) -> TodoTask? { tasks.first { $0.id == id } }
    public func label(_ id: UUID) -> TaskLabel? { labels.first { $0.id == id } }

    public func labelNamed(_ name: String) -> TaskLabel? {
        labels.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func projectNamed(_ name: String) -> Project? {
        projects.first { !$0.isArchived && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func childProjects(of parentID: UUID?) -> [Project] {
        projects
            .filter { $0.parentID == parentID && !$0.isInbox && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The project plus every descendant, archived ones included. Callers that
    /// delete or check for cycles need the complete set; filter matching uses
    /// `liveDescendantProjectIDs` instead.
    public func descendantProjectIDs(of id: UUID) -> Set<UUID> {
        var out: Set<UUID> = [id]
        var queue = [id]
        while let current = queue.popLast() {
            for child in projects where child.parentID == current {
                if out.insert(child.id).inserted { queue.append(child.id) }
            }
        }
        return out
    }

    /// The project plus its non-archived descendants, for `##Project` matching.
    /// `projectNamed` already ignores archived projects, so including them here
    /// would make `##Work` match tasks that `#ArchivedChild` cannot find.
    public func liveDescendantProjectIDs(of id: UUID) -> Set<UUID> {
        var out: Set<UUID> = [id]
        var queue = [id]
        while let current = queue.popLast() {
            for child in projects where child.parentID == current && !child.isArchived {
                if out.insert(child.id).inserted { queue.append(child.id) }
            }
        }
        return out
    }

    public func sections(in projectID: UUID) -> [ProjectSection] {
        sections.filter { $0.projectID == projectID }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Incomplete root tasks in a project (optionally scoped to a section).
    public func rootTasks(project projectID: UUID, section sectionID: UUID?) -> [TodoTask] {
        tasks
            .filter { $0.projectID == projectID && $0.sectionID == sectionID
                && $0.parentID == nil && !$0.isCompleted }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func subtasks(of taskID: UUID, includeCompleted: Bool = true) -> [TodoTask] {
        tasks
            .filter { $0.parentID == taskID && (includeCompleted || !$0.isCompleted) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func completedTasks(project projectID: UUID) -> [TodoTask] {
        tasks
            .filter { $0.projectID == projectID && $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    public var incompleteTasks: [TodoTask] { tasks.filter { !$0.isCompleted } }

    public func overdueTasks(now: Date = Date()) -> [TodoTask] {
        let today = calendar.startOfDay(for: now)
        return incompleteTasks.filter { task in
            guard let due = task.dueDate else { return false }
            if task.hasDueTime { return due < now }
            return calendar.startOfDay(for: due) < today
        }
        .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    public func tasksDue(on day: Date) -> [TodoTask] {
        let target = calendar.startOfDay(for: day)
        return incompleteTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.startOfDay(for: due) == target
        }
        .sorted { lhs, rhs in
            if lhs.hasDueTime != rhs.hasDueTime { return lhs.hasDueTime }
            if lhs.hasDueTime, let l = lhs.dueDate, let r = rhs.dueDate, l != r { return l < r }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    public func todayCount(now: Date = Date()) -> Int {
        tasksDue(on: now).count + overdueTasks(now: now).filter { !calendar.isDate($0.dueDate ?? now, inSameDayAs: now) }.count
    }

    public func reminders(for taskID: UUID) -> [TaskReminder] {
        reminders.filter { $0.taskID == taskID }
    }

    public func filterContext(now: Date = Date()) -> FilterContext {
        FilterContext(
            calendar: calendar,
            now: now,
            projectName: { [weak self] id in self?.project(id)?.name },
            sectionName: { [weak self] id in self?.section(id)?.name },
            labelNames: { [weak self] task in
                task.labelIDs.compactMap { self?.label($0)?.name }
            },
            projectIDs: { [weak self] name, includeSub in
                guard let self, let p = self.projectNamed(name) else { return [] }
                return includeSub ? self.liveDescendantProjectIDs(of: p.id) : [p.id]
            }
        )
    }

    /// Run a parsed filter over all incomplete tasks.
    public func tasksMatching(_ expr: FilterExpr, now: Date = Date()) -> [TodoTask] {
        let ctx = filterContext(now: now)
        return incompleteTasks
            .filter { FilterEngine.evaluate($0, expr: expr, context: ctx) }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case (let l?, let r?) where l != r: return l < r
                case (nil, .some): return false
                case (.some, nil): return true
                default:
                    if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
    }

    // MARK: - Activity & stats

    func logEvent(_ type: ActivityType, task: TodoTask) {
        let projectName = project(task.projectID)?.name ?? ""
        events.append(ActivityEvent(type: type, timestamp: Date(),
                                    taskTitle: task.title, projectName: projectName,
                                    taskID: task.id))
        if events.count > 5000 {
            events.removeFirst(events.count - 5000)
        }
    }

    func bumpDailyStat(on date: Date, completedDelta: Int = 0, addedDelta: Int = 0) {
        let key = KarmaEngine.dayKey(for: date, calendar: calendar)
        if let idx = dailyStats.firstIndex(where: { $0.day == key }) {
            dailyStats[idx].completed = max(0, dailyStats[idx].completed + completedDelta)
            dailyStats[idx].added = max(0, dailyStats[idx].added + addedDelta)
        } else {
            dailyStats.append(DailyStat(day: key, completed: max(0, completedDelta), added: max(0, addedDelta)))
        }
    }

    public func stat(forDay key: String) -> DailyStat? {
        dailyStats.first { $0.day == key }
    }

    func completedCount(inWeekOf date: Date) -> Int {
        let week = KarmaEngine.weekKey(for: date, calendar: calendar)
        return dailyStats
            .filter { stat in
                guard let d = KarmaEngine.dateFromDayKey(stat.day, calendar: calendar) else { return false }
                return KarmaEngine.weekKey(for: d, calendar: calendar) == week
            }
            .reduce(0) { $0 + $1.completed }
    }

    // MARK: - Task mutations

    @discardableResult
    public func addTask(title: String, details: String = "", priority: Priority = .p4,
                        dueDate: Date? = nil, hasDueTime: Bool = false,
                        recurrence: String? = nil, projectID: UUID? = nil,
                        sectionID: UUID? = nil, parentID: UUID? = nil,
                        labelIDs: [UUID] = []) -> TodoTask {
        let pid = projectID ?? inbox.id
        let siblings = tasks.filter { $0.projectID == pid && $0.sectionID == sectionID && $0.parentID == parentID }
        let order = (siblings.map(\.sortOrder).max() ?? 0) + 1
        // Remember the day a plain monthly series starts on, so a later clamp
        // into a short month can't turn it into an end-of-month series.
        var anchorDay: Int?
        if let due = dueDate, let text = recurrence,
           let rule = RecurrenceRule.deserialize(text),
           rule.unit == .month, rule.monthDay == nil {
            anchorDay = calendar.component(.day, from: due)
        }
        let task = TodoTask(title: title, details: details, priority: priority,
                            dueDate: dueDate, hasDueTime: hasDueTime, recurrence: recurrence,
                            recurrenceAnchorDay: anchorDay,
                            sortOrder: order, projectID: pid, sectionID: sectionID,
                            parentID: parentID, labelIDs: labelIDs)
        tasks.append(task)
        logEvent(.added, task: task)
        bumpDailyStat(on: Date(), addedDelta: 1)
        scheduleSave()
        onRemindersChanged?() // keeps the dock badge current for today-due adds
        return task
    }

    /// Add from a quick-add parse, resolving/creating projects, sections, labels.
    @discardableResult
    public func addTask(from parsed: ParsedQuickAdd, defaultProjectID: UUID? = nil) -> TodoTask {
        var projectID = defaultProjectID ?? inbox.id
        if let name = parsed.projectName {
            if let existing = projectNamed(name) {
                projectID = existing.id
            } else {
                projectID = addProject(name: name).id
            }
        }
        var sectionID: UUID?
        if let name = parsed.sectionName {
            if let existing = sections(in: projectID).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                sectionID = existing.id
            } else {
                sectionID = addSection(name: name, projectID: projectID).id
            }
        }
        var labelIDs: [UUID] = []
        for name in parsed.labelNames {
            if let existing = labelNamed(name) {
                labelIDs.append(existing.id)
            } else {
                labelIDs.append(addLabel(name: name).id)
            }
        }
        return addTask(title: parsed.title.isEmpty ? "Untitled" : parsed.title,
                       priority: parsed.priority,
                       dueDate: parsed.dueDate, hasDueTime: parsed.hasDueTime,
                       recurrence: parsed.recurrence?.displayText,
                       projectID: projectID, sectionID: sectionID, labelIDs: labelIDs)
    }

    public func updateTask(_ task: TodoTask, mutate: (TodoTask) -> Void) {
        mutate(task)
        logEvent(.updated, task: task)
        scheduleSave()
        onRemindersChanged?()
    }

    /// Complete a task. Recurring tasks advance to the next occurrence instead
    /// of completing; karma and activity still count the completion.
    public func complete(_ task: TodoTask, now: Date = Date()) {
        guard !task.isCompleted else { return } // no double-count on double-tap
        if let text = task.recurrence, let rule = RecurrenceRule.deserialize(text),
           let due = task.dueDate {
            let base = rule.strict ? Self.carryTime(from: due, onto: now, calendar: calendar) : due
            // Anchor the series to the day it started on, so a monthly rule keeps
            // its day-of-month instead of drifting to month-end once a short
            // month clamps it. Tasks saved before this field existed adopt their
            // current day the first time they advance.
            let anchorDay = task.recurrenceAnchorDay ?? calendar.component(.day, from: base)
            if task.recurrenceAnchorDay == nil, rule.unit == .month, rule.monthDay == nil {
                task.recurrenceAnchorDay = anchorDay
            }
            if var next = rule.nextOccurrence(after: base, calendar: calendar, anchorDay: anchorDay) {
                // Overdue recurring task: skip already-passed occurrences so one
                // completion catches up instead of staying overdue.
                var guardCounter = 0
                while isPast(next, now: now, hasTime: task.hasDueTime), guardCounter < 1000,
                      let following = rule.nextOccurrence(after: next, calendar: calendar, anchorDay: anchorDay) {
                    next = following
                    guardCounter += 1
                }
                task.dueDate = next
                registerCompletion(task, now: now)
                scheduleSave()
                onRemindersChanged?()
                return
            }
        }
        task.completedAt = now
        // Completing a parent completes nothing else; subtasks stay as-is (Todoist behavior).
        registerCompletion(task, now: now)
        scheduleSave()
        onRemindersChanged?()
    }

    func registerCompletion(_ task: TodoTask, now: Date) {
        logEvent(.completed, task: task)
        bumpDailyStat(on: now, completedDelta: 1)
        let todayKey = KarmaEngine.dayKey(for: now, calendar: calendar)
        let completedToday = stat(forDay: todayKey)?.completed ?? 1
        let completedThisWeek = completedCount(inWeekOf: now)
        KarmaEngine.applyCompletion(state: &karma, date: now,
                                    completedToday: completedToday,
                                    completedThisWeek: completedThisWeek,
                                    calendar: calendar)
    }

    public func uncomplete(_ task: TodoTask) {
        guard task.isCompleted else { return }
        let when = task.completedAt ?? Date()
        task.completedAt = nil
        logEvent(.uncompleted, task: task)
        bumpDailyStat(on: when, completedDelta: -1)
        // Give back the completion points so complete/uncomplete cycles can't
        // farm karma. (Goal bonuses stay: the same-day re-complete is blocked
        // from a second bonus by lastDailyStreakDay/lastWeeklyStreakWeek.)
        if karma.karmaEnabled, !karma.vacationMode {
            karma.points = max(0, karma.points - KarmaEngine.completionPoints)
        }
        scheduleSave()
        onRemindersChanged?() // restore this task's pending reminders + badge
    }

    public func deleteTask(_ task: TodoTask) {
        // Cascade to subtasks.
        for sub in tasks.filter({ $0.parentID == task.id }) {
            deleteTask(sub)
        }
        reminders.removeAll { $0.taskID == task.id }
        logEvent(.deleted, task: task)
        tasks.removeAll { $0.id == task.id }
        scheduleSave()
        onRemindersChanged?()
    }

    public func move(_ task: TodoTask, toProject projectID: UUID, section sectionID: UUID?) {
        let changingBucket = task.projectID != projectID || task.sectionID != sectionID
        task.projectID = projectID
        task.sectionID = sectionID
        if changingBucket, task.parentID == nil {
            // Append to the end of the new bucket instead of keeping a stale
            // sort order that lands at an arbitrary position.
            let siblings = tasks.filter {
                $0.projectID == projectID && $0.sectionID == sectionID
                    && $0.parentID == nil && $0.id != task.id
            }
            task.sortOrder = (siblings.map(\.sortOrder).max() ?? 0) + 1
        }
        // Moving a parent moves its subtasks.
        for sub in tasks where sub.parentID == task.id {
            move(sub, toProject: projectID, section: sectionID)
        }
        scheduleSave()
    }

    /// Reorder within a sibling list: place `task` before `target` (or at end).
    public func reorder(_ task: TodoTask, before target: TodoTask?,
                        project projectID: UUID, section sectionID: UUID?) {
        if task.projectID != projectID || task.sectionID != sectionID {
            move(task, toProject: projectID, section: sectionID)
        }
        var siblings = rootTasks(project: projectID, section: sectionID).filter { $0.id != task.id }
        let index = target.flatMap { t in siblings.firstIndex(where: { $0.id == t.id }) } ?? siblings.count
        siblings.insert(task, at: index)
        for (i, t) in siblings.enumerated() {
            t.sortOrder = Double(i)
        }
        scheduleSave()
    }

    // MARK: - Project / section mutations

    @discardableResult
    public func addProject(name: String, color: ItemColor = .charcoal, parentID: UUID? = nil,
                           viewStyle: ViewStyle = .list) -> Project {
        let order = (childProjects(of: parentID).map(\.sortOrder).max() ?? 0) + 1
        let p = Project(name: name, color: color, viewStyle: viewStyle, sortOrder: order, parentID: parentID)
        projects.append(p)
        scheduleSave()
        return p
    }

    public func deleteProject(_ project: Project) {
        guard !project.isInbox else { return }
        // descendantProjectIDs is cycle-safe; avoids unbounded recursion if a
        // parent cycle ever sneaks into the data.
        let doomed = descendantProjectIDs(of: project.id)
        let taskIDs = Set(tasks.filter { doomed.contains($0.projectID) }.map(\.id))
        reminders.removeAll { taskIDs.contains($0.taskID) }
        tasks.removeAll { doomed.contains($0.projectID) }
        sections.removeAll { doomed.contains($0.projectID) }
        projects.removeAll { doomed.contains($0.id) && !$0.isInbox }
        scheduleSave()
        onRemindersChanged?()
    }

    public func archiveProject(_ project: Project, archived: Bool = true) {
        guard !project.isInbox else { return }
        let affected = descendantProjectIDs(of: project.id)
        for p in projects where affected.contains(p.id) && !p.isInbox {
            p.isArchived = archived
        }
        scheduleSave()
    }

    /// True when `parentID` is a legal parent for `project` (no self/descendant cycles).
    public func canSetParent(of project: Project, to parentID: UUID?) -> Bool {
        guard let parentID else { return true }
        return !descendantProjectIDs(of: project.id).contains(parentID)
    }

    @discardableResult
    public func addSection(name: String, projectID: UUID) -> ProjectSection {
        let order = (sections(in: projectID).map(\.sortOrder).max() ?? 0) + 1
        let s = ProjectSection(name: name, sortOrder: order, projectID: projectID)
        sections.append(s)
        scheduleSave()
        return s
    }

    public func deleteSection(_ section: ProjectSection) {
        // Tasks in the section fall back to the project body.
        for t in tasks where t.sectionID == section.id {
            t.sectionID = nil
        }
        sections.removeAll { $0.id == section.id }
        scheduleSave()
    }

    // MARK: - Label mutations

    @discardableResult
    public func addLabel(name: String, color: ItemColor = .charcoal) -> TaskLabel {
        if let existing = labelNamed(name) { return existing }
        let order = (labels.map(\.sortOrder).max() ?? 0) + 1
        let l = TaskLabel(name: name, color: color, sortOrder: order)
        labels.append(l)
        scheduleSave()
        return l
    }

    public func deleteLabel(_ label: TaskLabel) {
        for t in tasks {
            t.labelIDs.removeAll { $0 == label.id }
        }
        labels.removeAll { $0.id == label.id }
        scheduleSave()
    }

    // MARK: - Filter mutations

    @discardableResult
    public func addFilter(name: String, query: String, color: ItemColor = .charcoal) -> SavedFilter {
        let order = (filters.map(\.sortOrder).max() ?? 0) + 1
        let f = SavedFilter(name: name, query: query, color: color, sortOrder: order)
        filters.append(f)
        scheduleSave()
        return f
    }

    public func deleteFilter(_ filter: SavedFilter) {
        filters.removeAll { $0.id == filter.id }
        scheduleSave()
    }

    // MARK: - Reminder mutations

    @discardableResult
    public func addReminder(taskID: UUID, kind: ReminderKind) -> TaskReminder {
        let r = TaskReminder(taskID: taskID, kind: kind)
        reminders.append(r)
        scheduleSave()
        onRemindersChanged?()
        return r
    }

    public func deleteReminder(_ reminder: TaskReminder) {
        reminders.removeAll { $0.id == reminder.id }
        scheduleSave()
        onRemindersChanged?()
    }

    // MARK: - Helpers

    /// Is a candidate next-occurrence already in the past?
    func isPast(_ date: Date, now: Date, hasTime: Bool) -> Bool {
        if hasTime { return date <= now }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    /// Combine `source`'s time-of-day with `day`'s date.
    static func carryTime(from source: Date, onto day: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        let time = calendar.dateComponents([.hour, .minute], from: source)
        comps.hour = time.hour
        comps.minute = time.minute
        return calendar.date(from: comps) ?? day
    }
}

extension FilterEngine {
    /// Convenience with argument order matching call sites in AppStore.
    static func evaluate(_ task: TodoTask, expr: FilterExpr, context: FilterContext) -> Bool {
        evaluate(expr, task: task, context: context)
    }
}
