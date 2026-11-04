import Foundation

/// When the Overdue list is long enough to bury upcoming work, it folds to its
/// header. Lives in the kit so the rule is testable, and so every view that
/// publishes `visibleTaskIDs` agrees with what it draws.
public enum OverdueFold {
    /// The longest Overdue list that is always shown.
    public static let threshold = 5

    public static func canFold(count: Int) -> Bool { count > threshold }

    /// The rows to draw. Keyboard navigation must use this too, so j/k can't
    /// land on a row inside a folded list.
    public static func shown<Item>(_ items: [Item], expanded: Bool) -> [Item] {
        canFold(count: items.count) && !expanded ? [] : items
    }
}
