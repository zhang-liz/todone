import SwiftUI
import Observation
import TodoneKit

/// Which content view is selected in the sidebar.
enum SidebarItem: Hashable {
    case inbox
    case today
    case upcoming
    case filtersAndLabels
    case activity
    case project(UUID)
    case label(UUID)
    case filter(UUID)
    case completed
}

/// App-level UI state shared across windows/views.
@Observable
final class AppModel {
    var selection: SidebarItem? = .today
    var selectedTaskID: UUID?
    var showQuickAdd = false
    var showSearch = false
    var searchText = ""

    /// Set when a view wants to start inline "add task" mode.
    var pendingInlineAdd = false

    /// Bumped at midnight so date-anchored views (Today, Upcoming) recompute.
    var dayTick = 0

    /// Task IDs in the order the current view shows them. Published by whichever
    /// view is on screen so arrow / j / k can walk the list the user can see,
    /// rather than the store's unordered array.
    var visibleTaskIDs: [UUID] = []

    func select(_ item: SidebarItem) {
        selection = item
        selectedTaskID = nil
    }

    /// Move the selection by `offset` through `visibleTaskIDs`. Holds position
    /// at the ends rather than moving nowhere silently.
    func moveSelection(by offset: Int) {
        if let next = ListNavigator.step(from: selectedTaskID, by: offset, in: visibleTaskIDs) {
            selectedTaskID = next
        }
    }
}
