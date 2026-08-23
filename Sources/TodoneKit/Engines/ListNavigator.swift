import Foundation

/// Selection movement through a visible task list.
///
/// Lives in the kit rather than the view layer so the stepping rules — where an
/// empty selection starts, and what happens at the ends — are testable.
public enum ListNavigator {

    /// The id `offset` positions from `selected` within `ids`.
    ///
    /// With nothing selected, moving forward starts at the first row and moving
    /// backward starts at the last. Movement stops at both ends instead of
    /// wrapping, so a held key settles rather than cycling. Returns nil when
    /// there is nowhere to go.
    public static func step(from selected: UUID?, by offset: Int, in ids: [UUID]) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let selected, let index = ids.firstIndex(of: selected) else {
            return offset >= 0 ? ids.first : ids.last
        }
        let next = index + offset
        guard ids.indices.contains(next) else { return nil }
        return ids[next]
    }

    /// The row that should hold the selection after the one at `completed` is
    /// removed: the following row, or the previous one at the end of the list.
    /// Returns nil when the list had nothing else in it.
    public static func successor(after completed: UUID, in ids: [UUID]) -> UUID? {
        guard let index = ids.firstIndex(of: completed) else { return nil }
        if ids.indices.contains(index + 1) { return ids[index + 1] }
        if ids.indices.contains(index - 1) { return ids[index - 1] }
        return nil
    }
}
