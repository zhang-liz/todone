import Foundation
import Observation

// MARK: - Enums

public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case p1 = 1, p2 = 2, p3 = 3, p4 = 4

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String { "P\(rawValue)" }
}

public enum ViewStyle: String, Codable, Sendable {
    case list, board
}

public enum ActivityType: String, Codable, Sendable {
    case added, completed, uncompleted, updated, deleted
}

/// Todoist-style named colors for projects, labels, and filters.
public enum ItemColor: String, Codable, CaseIterable, Sendable {
    case berryRed, red, orange, yellow, oliveGreen, limeGreen, green, mintGreen,
         teal, skyBlue, lightBlue, blue, grape, violet, lavender, magenta,
         salmon, charcoal, grey, taupe

    public var hex: String {
        switch self {
        case .berryRed: return "#B8256F"
        case .red: return "#DB4035"
        case .orange: return "#FF9933"
        case .yellow: return "#FAD000"
        case .oliveGreen: return "#AFB83B"
        case .limeGreen: return "#7ECC49"
        case .green: return "#299438"
        case .mintGreen: return "#6ACCBC"
        case .teal: return "#158FAD"
        case .skyBlue: return "#14AAF5"
        case .lightBlue: return "#96C3EB"
        case .blue: return "#4073FF"
        case .grape: return "#884DFF"
        case .violet: return "#AF38EB"
        case .lavender: return "#EB96EB"
        case .magenta: return "#E05194"
        case .salmon: return "#FF8D85"
        case .charcoal: return "#808080"
        case .grey: return "#B8B8B8"
        case .taupe: return "#CCAC93"
        }
    }

    public var displayName: String {
        switch self {
        case .berryRed: return "Berry Red"
        case .oliveGreen: return "Olive Green"
        case .limeGreen: return "Lime Green"
        case .mintGreen: return "Mint Green"
        case .skyBlue: return "Sky Blue"
        case .lightBlue: return "Light Blue"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

// MARK: - Project

@Observable
public final class Project: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var color: ItemColor
    public var isFavorite: Bool
    public var isInbox: Bool
    public var viewStyle: ViewStyle
    public var sortOrder: Double
    public var parentID: UUID?
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, color: ItemColor = .charcoal,
                isFavorite: Bool = false, isInbox: Bool = false, viewStyle: ViewStyle = .list,
                sortOrder: Double = 0, parentID: UUID? = nil, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.isFavorite = isFavorite
        self.isInbox = isInbox
        self.viewStyle = viewStyle
        self.sortOrder = sortOrder
        self.parentID = parentID
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, isFavorite, isInbox, viewStyle, sortOrder, parentID, isArchived
    }

    public convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            color: try c.decode(ItemColor.self, forKey: .color),
            isFavorite: try c.decode(Bool.self, forKey: .isFavorite),
            isInbox: try c.decode(Bool.self, forKey: .isInbox),
            viewStyle: try c.decode(ViewStyle.self, forKey: .viewStyle),
            sortOrder: try c.decode(Double.self, forKey: .sortOrder),
            parentID: try c.decodeIfPresent(UUID.self, forKey: .parentID),
            isArchived: try c.decode(Bool.self, forKey: .isArchived)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(isInbox, forKey: .isInbox)
        try c.encode(viewStyle, forKey: .viewStyle)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(isArchived, forKey: .isArchived)
    }
}

// MARK: - Section

@Observable
public final class ProjectSection: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var sortOrder: Double
    public var projectID: UUID

    public init(id: UUID = UUID(), name: String, sortOrder: Double = 0, projectID: UUID) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.projectID = projectID
    }

    enum CodingKeys: String, CodingKey { case id, name, sortOrder, projectID }

    public convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            sortOrder: try c.decode(Double.self, forKey: .sortOrder),
            projectID: try c.decode(UUID.self, forKey: .projectID)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(projectID, forKey: .projectID)
    }
}

// MARK: - Task

@Observable
public final class TodoTask: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var details: String
    public var priority: Priority
    public var dueDate: Date?
    public var hasDueTime: Bool
    /// Serialized RecurrenceRule, nil when not recurring.
    public var recurrence: String?
    public var sortOrder: Double
    public var completedAt: Date?
    public var createdAt: Date
    public var projectID: UUID
    public var sectionID: UUID?
    public var parentID: UUID?
    public var labelIDs: [UUID]

    public var isCompleted: Bool { completedAt != nil }

    public init(id: UUID = UUID(), title: String, details: String = "",
                priority: Priority = .p4, dueDate: Date? = nil, hasDueTime: Bool = false,
                recurrence: String? = nil, sortOrder: Double = 0, completedAt: Date? = nil,
                createdAt: Date = Date(), projectID: UUID, sectionID: UUID? = nil,
                parentID: UUID? = nil, labelIDs: [UUID] = []) {
        self.id = id
        self.title = title
        self.details = details
        self.priority = priority
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.recurrence = recurrence
        self.sortOrder = sortOrder
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.projectID = projectID
        self.sectionID = sectionID
        self.parentID = parentID
        self.labelIDs = labelIDs
    }

    enum CodingKeys: String, CodingKey {
        case id, title, details, priority, dueDate, hasDueTime, recurrence, sortOrder,
             completedAt, createdAt, projectID, sectionID, parentID, labelIDs
    }

    public convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            title: try c.decode(String.self, forKey: .title),
            details: try c.decode(String.self, forKey: .details),
            priority: try c.decode(Priority.self, forKey: .priority),
            dueDate: try c.decodeIfPresent(Date.self, forKey: .dueDate),
            hasDueTime: try c.decode(Bool.self, forKey: .hasDueTime),
            recurrence: try c.decodeIfPresent(String.self, forKey: .recurrence),
            sortOrder: try c.decode(Double.self, forKey: .sortOrder),
            completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt),
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            projectID: try c.decode(UUID.self, forKey: .projectID),
            sectionID: try c.decodeIfPresent(UUID.self, forKey: .sectionID),
            parentID: try c.decodeIfPresent(UUID.self, forKey: .parentID),
            labelIDs: try c.decode([UUID].self, forKey: .labelIDs)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(details, forKey: .details)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        try c.encode(hasDueTime, forKey: .hasDueTime)
        try c.encodeIfPresent(recurrence, forKey: .recurrence)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(projectID, forKey: .projectID)
        try c.encodeIfPresent(sectionID, forKey: .sectionID)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(labelIDs, forKey: .labelIDs)
    }
}

// MARK: - Label

@Observable
public final class TaskLabel: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var color: ItemColor
    public var isFavorite: Bool
    public var sortOrder: Double

    public init(id: UUID = UUID(), name: String, color: ItemColor = .charcoal,
                isFavorite: Bool = false, sortOrder: Double = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey { case id, name, color, isFavorite, sortOrder }

    public convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            color: try c.decode(ItemColor.self, forKey: .color),
            isFavorite: try c.decode(Bool.self, forKey: .isFavorite),
            sortOrder: try c.decode(Double.self, forKey: .sortOrder)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - Filter

@Observable
public final class SavedFilter: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var query: String
    public var color: ItemColor
    public var isFavorite: Bool
    public var sortOrder: Double

    public init(id: UUID = UUID(), name: String, query: String, color: ItemColor = .charcoal,
                isFavorite: Bool = false, sortOrder: Double = 0) {
        self.id = id
        self.name = name
        self.query = query
        self.color = color
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey { case id, name, query, color, isFavorite, sortOrder }

    public convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            query: try c.decode(String.self, forKey: .query),
            color: try c.decode(ItemColor.self, forKey: .color),
            isFavorite: try c.decode(Bool.self, forKey: .isFavorite),
            sortOrder: try c.decode(Double.self, forKey: .sortOrder)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(query, forKey: .query)
        try c.encode(color, forKey: .color)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - Reminder

public enum ReminderKind: Codable, Equatable, Sendable {
    /// Fires at an absolute date/time.
    case absolute(Date)
    /// Fires N minutes before the task's due time.
    case relative(minutesBefore: Int)
}

public struct TaskReminder: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var taskID: UUID
    public var kind: ReminderKind

    public init(id: UUID = UUID(), taskID: UUID, kind: ReminderKind) {
        self.id = id
        self.taskID = taskID
        self.kind = kind
    }
}

// MARK: - Activity

public struct ActivityEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public var type: ActivityType
    public var timestamp: Date
    public var taskTitle: String
    public var projectName: String
    public var taskID: UUID?

    public init(id: UUID = UUID(), type: ActivityType, timestamp: Date = Date(),
                taskTitle: String, projectName: String, taskID: UUID? = nil) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.taskTitle = taskTitle
        self.projectName = projectName
        self.taskID = taskID
    }
}

// MARK: - Karma

public struct DailyStat: Codable, Equatable, Sendable {
    /// Day key "yyyy-MM-dd" in the local calendar.
    public var day: String
    public var completed: Int
    public var added: Int

    public init(day: String, completed: Int = 0, added: Int = 0) {
        self.day = day
        self.completed = completed
        self.added = added
    }
}

public struct KarmaState: Codable, Equatable, Sendable {
    public var points: Int
    public var dailyGoal: Int
    public var weeklyGoal: Int
    public var vacationMode: Bool
    public var karmaEnabled: Bool
    public var currentDailyStreak: Int
    public var maxDailyStreak: Int
    public var currentWeeklyStreak: Int
    public var maxWeeklyStreak: Int
    /// Day key of the last day counted toward the daily streak.
    public var lastDailyStreakDay: String?
    /// Week key ("yyyy-Www") of the last week counted toward the weekly streak.
    public var lastWeeklyStreakWeek: String?

    public init(points: Int = 0, dailyGoal: Int = 5, weeklyGoal: Int = 25,
                vacationMode: Bool = false, karmaEnabled: Bool = true,
                currentDailyStreak: Int = 0, maxDailyStreak: Int = 0,
                currentWeeklyStreak: Int = 0, maxWeeklyStreak: Int = 0,
                lastDailyStreakDay: String? = nil, lastWeeklyStreakWeek: String? = nil) {
        self.points = points
        self.dailyGoal = dailyGoal
        self.weeklyGoal = weeklyGoal
        self.vacationMode = vacationMode
        self.karmaEnabled = karmaEnabled
        self.currentDailyStreak = currentDailyStreak
        self.maxDailyStreak = maxDailyStreak
        self.currentWeeklyStreak = currentWeeklyStreak
        self.maxWeeklyStreak = maxWeeklyStreak
        self.lastDailyStreakDay = lastDailyStreakDay
        self.lastWeeklyStreakWeek = lastWeeklyStreakWeek
    }
}

public enum KarmaLevel: Int, CaseIterable, Sendable {
    case beginner, novice, intermediate, professional, expert, master, grandmaster, enlightened

    public var threshold: Int {
        switch self {
        case .beginner: return 0
        case .novice: return 500
        case .intermediate: return 2500
        case .professional: return 5000
        case .expert: return 7500
        case .master: return 10000
        case .grandmaster: return 20000
        case .enlightened: return 50000
        }
    }

    public var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .novice: return "Novice"
        case .intermediate: return "Intermediate"
        case .professional: return "Professional"
        case .expert: return "Expert"
        case .master: return "Master"
        case .grandmaster: return "Grandmaster"
        case .enlightened: return "Enlightened"
        }
    }

    public static func level(for points: Int) -> KarmaLevel {
        allCases.last(where: { points >= $0.threshold }) ?? .beginner
    }
}
