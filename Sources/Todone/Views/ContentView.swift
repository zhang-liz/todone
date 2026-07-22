import SwiftUI
import TodoneKit

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            detailView
        }
        .sheet(isPresented: $model.showQuickAdd) {
            QuickAddView()
        }
        .sheet(isPresented: $model.showSearch) {
            SearchView()
        }
        .overlay(alignment: .bottom) {
            if let error = store.lastSaveError {
                Text(error)
                    .font(.callout)
                    .padding(10)
                    .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: store.lastSaveError)
        .task {
            KeyMonitor.shared.start(store: store, model: model)
            GlobalHotkey.shared.register { [weak model] in
                model?.showQuickAdd = true
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selection {
        case .inbox:
            ProjectView(projectID: store.inbox.id)
        case .today, nil:
            TodayView()
        case .upcoming:
            UpcomingView()
        case .filtersAndLabels:
            FiltersLabelsView()
        case .activity:
            ActivityView()
        case .completed:
            CompletedView()
        case .project(let id):
            if store.project(id) != nil {
                ProjectView(projectID: id)
            } else {
                missingView
            }
        case .label(let id):
            if let label = store.label(id) {
                LabelTasksView(label: label)
            } else {
                missingView
            }
        case .filter(let id):
            if let filter = store.filters.first(where: { $0.id == id }) {
                FilterTasksView(filter: filter)
            } else {
                missingView
            }
        }
    }

    private var missingView: some View {
        ContentUnavailableView("Not found", systemImage: "questionmark.circle")
    }
}
