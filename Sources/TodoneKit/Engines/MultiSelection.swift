import Foundation

/// Range and toggle selection over a visible task list.
///
/// Lives in the kit rather than the view layer so the click rules are testable:
/// plain click replaces, cmd-click toggles, shift-click extends from an anchor.
public struct MultiSelection: Equatable {
    /// Everything currently selected.
    public private(set) var ids: Set<UUID> = []
    /// The row a shift-click extends from — the last plain or cmd click.
    public private(set) var anchor: UUID?
    /// The moving end of a range. Shift+Arrow steps from here, because the
    /// anchor stays put while the range grows.
    public private(set) var focus: UUID?
    /// Selected rows, oldest first, so a removed anchor has a clear successor.
    /// A Set has no order, so its first element could be any row.
    private var recent: [UUID] = []

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }
    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// Sole selection, or nil when zero or several rows are selected. Lets the
    /// detail pane show a task only when exactly one is picked.
    public var only: UUID? { ids.count == 1 ? ids.first : nil }

    public mutating func clear() {
        ids = []
        anchor = nil
        focus = nil
        recent = []
    }

    /// Plain click: this row becomes the whole selection.
    public mutating func select(_ id: UUID) {
        ids = [id]
        anchor = id
        focus = id
        recent = [id]
    }

    /// Cmd-click: add or remove one row, leaving the rest alone.
    public mutating func toggle(_ id: UUID) {
        if ids.contains(id) {
            ids.remove(id)
            recent.removeAll { $0 == id }
            // Extending from a row that is no longer selected reads as a jump,
            // so drop the anchor with it.
            if anchor == id { anchor = recent.last }
            if focus == id { focus = anchor }
        } else {
            ids.insert(id)
            recent.append(id)
            anchor = id
            focus = id
        }
    }

    /// Shift-click: select every row between the anchor and `id` inclusive.
    /// Falls back to a plain selection when there is no anchor, or when either
    /// row has scrolled out of `visible`.
    public mutating func extend(to id: UUID, in visible: [UUID]) {
        guard let anchor,
              let start = visible.firstIndex(of: anchor),
              let end = visible.firstIndex(of: id) else {
            select(id)
            return
        }
        let range = start <= end ? start...end : end...start
        ids = Set(visible[range])
        recent = Array(visible[range])
        focus = id
        // The anchor stays put so dragging the shift-click around keeps
        // extending from the same origin.
    }

    /// Drop ids that are no longer on screen, after a completion or a filter
    /// change, so actions cannot fire on rows the user can't see.
    public mutating func prune(to visible: [UUID]) {
        let live = Set(visible)
        ids = ids.intersection(live)
        recent.removeAll { !live.contains($0) }
        if let anchor, !live.contains(anchor) { self.anchor = recent.last }
        if let focus, !live.contains(focus) { self.focus = self.anchor }
    }
}
