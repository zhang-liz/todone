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

    /// Multi-row selection. `selectedTaskID` is the single-selection view of it,
    /// so existing call sites keep working unchanged.
    var taskSelection = MultiSelection()

    var selectedTaskID: UUID? {
        get { taskSelection.only }
        set {
            if let newValue { taskSelection.select(newValue) } else { taskSelection.clear() }
        }
    }
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
        taskSelection.clear()
    }

    /// Move the selection by `offset` through `visibleTaskIDs`. Steps from the
    /// anchor, so arrowing after a multi-row selection continues from the row
    /// the user last clicked rather than starting over.
    func moveSelection(by offset: Int) {
        if let next = ListNavigator.step(from: taskSelection.anchor, by: offset, in: visibleTaskIDs) {
            taskSelection.select(next)
        }
    }

    /// Extend the selection by one row, for shift-arrow.
    func extendSelection(by offset: Int) {
        guard let next = ListNavigator.step(from: taskSelection.anchor, by: offset, in: visibleTaskIDs) else { return }
        taskSelection.extend(to: next, in: visibleTaskIDs)
    }

    /// Apply a click with its modifier keys.
    func handleClick(on id: UUID, extending: Bool, toggling: Bool) {
        if extending {
            taskSelection.extend(to: id, in: visibleTaskIDs)
        } else if toggling {
            taskSelection.toggle(id)
        } else {
            taskSelection.select(id)
        }
    }
}
