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

    func select(_ item: SidebarItem) {
        selection = item
        selectedTaskID = nil
    }
}
