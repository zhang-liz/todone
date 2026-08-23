import SwiftUI
import TodoneKit

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme

    @State private var showNewProject = false
    @State private var editingProject: Project?
    @State private var showKarma = false

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(
            get: { model.selection },
            set: { if let v = $0 { model.select(v) } }
        )) {
            Section {
                Label {
                    HStack {
                        Text("Inbox")
                        Spacer()
                        countBadge(store.rootTasks(project: store.inbox.id, section: nil).count)
                    }
                } icon: {
                    Image(systemName: "tray")
                }
                .tag(SidebarItem.inbox)

                Label {
                    HStack {
                        Text("Today")
                        Spacer()
                        countBadge(store.todayCount())
                    }
                } icon: {
                    Image(systemName: "calendar")
                }
                .tag(SidebarItem.today)

                Label("Upcoming", systemImage: "calendar.badge.clock")
                    .tag(SidebarItem.upcoming)

                Label("Filters & Labels", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.filtersAndLabels)

                Label("Completed", systemImage: "checkmark.circle")
                    .tag(SidebarItem.completed)

                Label("Activity", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.activity)
            }

            let favorites = favoriteItems
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites, id: \.tag) { item in
                        sidebarRow(item)
                    }
                }
            }

            Section {
                ForEach(store.childProjects(of: nil)) { project in
                    projectRow(project, depth: 0)
                }
            } header: {
                HStack {
                    Text("My Projects")
                    Spacer()
                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add project")
                }
            }

            // Archived projects are hidden from every picker and project list,
            // so without this section they — and their tasks — are unreachable.
            let archived = store.archivedProjects
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { project in
                        Label {
                            Text(project.name)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.project(project.id))
                        .contextMenu {
                            Button("Unarchive") { store.archiveProject(project, archived: false) }
                            Button("Delete", role: .destructive) { store.deleteProject(project) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showKarma = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text(KarmaLevel.level(for: store.karma.points).displayName)
                            .font(.callout)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showKarma) { KarmaView() }

                Spacer()

                Button {
                    model.showQuickAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .help("Quick add task (Q)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .sheet(isPresented: $showNewProject) {
            ProjectEditorView(project: nil)
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(project: project)
        }
    }

    // MARK: - Rows

    private struct FavoriteItem {
        var tag: SidebarItem
        var name: String
        var color: Color
        var icon: String
    }

    private var favoriteItems: [FavoriteItem] {
        var items: [FavoriteItem] = []
        for p in store.projects where p.isFavorite && !p.isArchived && !p.isInbox {
            items.append(FavoriteItem(tag: .project(p.id), name: p.name, color: Color(p.color), icon: "number"))
        }
        for l in store.labels where l.isFavorite {
            items.append(FavoriteItem(tag: .label(l.id), name: l.name, color: Color(l.color), icon: "tag"))
        }
        for f in store.filters where f.isFavorite {
            items.append(FavoriteItem(tag: .filter(f.id), name: f.name, color: Color(f.color), icon: "line.3.horizontal.decrease.circle"))
        }
        return items
    }

    private func sidebarRow(_ item: FavoriteItem) -> some View {
        Label {
            Text(item.name)
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(item.color)
        }
        .tag(item.tag)
    }

    @ViewBuilder
    private func projectRow(_ project: Project, depth: Int) -> some View {
        let children = store.childProjects(of: project.id)
        Label {
            HStack {
                Text(project.name)
                Spacer()
                countBadge(taskCount(project))
            }
        } icon: {
            Image(systemName: "number")
                .foregroundStyle(Color(project.color))
        }
        .padding(.leading, CGFloat(depth) * 14)
        .tag(SidebarItem.project(project.id))
        .contextMenu {
            Button("Edit") { editingProject = project }
            Button(project.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                project.isFavorite.toggle()
                store.scheduleSave()
            }
            Button("Add Section") {
                store.addSection(name: "New Section", projectID: project.id)
            }
            Divider()
            Button("Archive") { store.archiveProject(project) }
            Button("Delete", role: .destructive) {
                // The delete cascades to descendants; clear any selection into them.
                let doomed = store.descendantProjectIDs(of: project.id)
                if case .project(let sel) = model.selection, doomed.contains(sel) {
                    model.select(.inbox)
                }
                if let tid = model.selectedTaskID, let t = store.task(tid),
                   doomed.contains(t.projectID) {
                    model.selectedTaskID = nil
                }
                store.deleteProject(project)
            }
        }

        ForEach(children) { child in
            AnyView(projectRow(child, depth: depth + 1))
        }
    }

    private func taskCount(_ project: Project) -> Int {
        store.tasks.filter { $0.projectID == project.id && !$0.isCompleted }.count
    }

    @ViewBuilder
    private func countBadge(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
