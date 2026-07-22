import SwiftUI
import TodoneKit

/// The "Filters & Labels" management screen.
struct FiltersLabelsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var editingFilter: SavedFilter?
    @State private var showNewFilter = false
    @State private var editingLabel: TaskLabel?
    @State private var showNewLabel = false

    var body: some View {
        List {
            Section {
                ForEach(store.filters.sorted { $0.sortOrder < $1.sortOrder }) { filter in
                    Button {
                        model.select(.filter(filter.id))
                    } label: {
                        HStack {
                            Label(filter.name, systemImage: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(Color(filter.color))
                            Spacer()
                            Text(filter.query)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") { editingFilter = filter }
                        Button(filter.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                            filter.isFavorite.toggle()
                            store.scheduleSave()
                        }
                        Button("Delete", role: .destructive) { store.deleteFilter(filter) }
                    }
                }
            } header: {
                HStack {
                    Text("Filters")
                    Spacer()
                    Button { showNewFilter = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                }
            }

            Section {
                ForEach(store.labels.sorted { $0.sortOrder < $1.sortOrder }) { label in
                    Button {
                        model.select(.label(label.id))
                    } label: {
                        HStack {
                            Label(label.name, systemImage: "tag")
                                .foregroundStyle(Color(label.color))
                            Spacer()
                            Text("\(taskCount(label))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") { editingLabel = label }
                        Button(label.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                            label.isFavorite.toggle()
                            store.scheduleSave()
                        }
                        Button("Delete", role: .destructive) { store.deleteLabel(label) }
                    }
                }
            } header: {
                HStack {
                    Text("Labels")
                    Spacer()
                    Button { showNewLabel = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Filters & Labels")
        .sheet(isPresented: $showNewFilter) { FilterEditorView(filter: nil) }
        .sheet(item: $editingFilter) { FilterEditorView(filter: $0) }
        .sheet(isPresented: $showNewLabel) { LabelEditorView(label: nil) }
        .sheet(item: $editingLabel) { LabelEditorView(label: $0) }
    }

    private func taskCount(_ label: TaskLabel) -> Int {
        store.incompleteTasks.filter { $0.labelIDs.contains(label.id) }.count
    }
}

// MARK: - Filter tasks list

struct FilterTasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let filter: SavedFilter

    var body: some View {
        Group {
            switch parseResult {
            case .success(let expr):
                let tasks = store.tasksMatching(expr)
                if tasks.isEmpty {
                    ContentUnavailableView("No matching tasks", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(tasks) { task in
                                TaskRowView(task: task, showsProject: true)
                                    .padding(.horizontal, 20)
                                Divider().padding(.leading, 48)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            case .failure(let error):
                ContentUnavailableView {
                    Label("Invalid filter", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                }
            }
        }
        .navigationTitle(filter.name)
        .inspector(isPresented: Binding(
            get: { model.selectedTaskID != nil },
            set: { if !$0 { model.selectedTaskID = nil } }
        )) {
            TaskDetailView()
        }
    }

    private var parseResult: Result<FilterExpr, FilterParseError> {
        do {
            return .success(try FilterEngine.parse(filter.query))
        } catch let error as FilterParseError {
            return .failure(error)
        } catch {
            return .failure(FilterParseError(error.localizedDescription))
        }
    }
}

// MARK: - Label tasks list

struct LabelTasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let label: TaskLabel

    var body: some View {
        let tasks = store.incompleteTasks
            .filter { $0.labelIDs.contains(label.id) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        Group {
            if tasks.isEmpty {
                ContentUnavailableView("No tasks with @\(label.name)", systemImage: "tag")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks) { task in
                            TaskRowView(task: task, showsProject: true)
                                .padding(.horizontal, 20)
                            Divider().padding(.leading, 48)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("@\(label.name)")
        .inspector(isPresented: Binding(
            get: { model.selectedTaskID != nil },
            set: { if !$0 { model.selectedTaskID = nil } }
        )) {
            TaskDetailView()
        }
    }
}

// MARK: - Editors

struct FilterEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let filter: SavedFilter?

    @State private var name = ""
    @State private var query = ""
    @State private var color = ItemColor.charcoal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter == nil ? "New Filter" : "Edit Filter")
                .font(.headline)

            TextField("Name", text: $name)
            TextField("Query — e.g. \"today & p1\" or \"#Work | @waiting\"", text: $query)

            queryFeedback

            ColorPickerRow(selection: $color)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(filter == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !queryIsValid)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            if let filter {
                name = filter.name
                query = filter.query
                color = filter.color
            }
        }
    }

    private var queryIsValid: Bool {
        (try? FilterEngine.parse(query)) != nil
    }

    @ViewBuilder
    private var queryFeedback: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Terms: today, overdue, p1–p4, #project, @label, /section, 7 days, no date, recurring, search: text — combine with & | ! ( )")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch parseFeedback {
            case .success(let expr):
                let count = store.tasksMatching(expr).count
                Label("\(count) matching task\(count == 1 ? "" : "s")", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let err):
                Label(err.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var parseFeedback: Result<FilterExpr, FilterParseError> {
        do {
            return .success(try FilterEngine.parse(query))
        } catch let error as FilterParseError {
            return .failure(error)
        } catch {
            return .failure(FilterParseError(error.localizedDescription))
        }
    }

    private func save() {
        if let filter {
            filter.name = name
            filter.query = query
            filter.color = color
            store.scheduleSave()
        } else {
            store.addFilter(name: name, query: query, color: color)
        }
        dismiss()
    }
}

struct LabelEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let label: TaskLabel?

    @State private var name = ""
    @State private var color = ItemColor.charcoal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label == nil ? "New Label" : "Edit Label")
                .font(.headline)
            TextField("Name", text: $name)
            ColorPickerRow(selection: $color)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(label == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            if let label {
                name = label.name
                color = label.color
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let label {
            label.name = trimmed
            label.color = color
            store.scheduleSave()
        } else {
            let l = store.addLabel(name: trimmed)
            l.color = color
            store.scheduleSave()
        }
        dismiss()
    }
}

struct ProjectEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let project: Project?

    @State private var name = ""
    @State private var color = ItemColor.charcoal
    @State private var parentID: UUID?
    @State private var isFavorite = false
    @State private var viewStyle = ViewStyle.list

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project == nil ? "New Project" : "Edit Project")
                .font(.headline)

            TextField("Name", text: $name)

            ColorPickerRow(selection: $color)

            Picker("Parent", selection: $parentID) {
                Text("None").tag(UUID?.none)
                ForEach(store.projects.filter { !$0.isInbox && !$0.isArchived && $0.id != project?.id }) { p in
                    Text(p.name).tag(UUID?.some(p.id))
                }
            }

            Picker("View", selection: $viewStyle) {
                Text("List").tag(ViewStyle.list)
                Text("Board").tag(ViewStyle.board)
            }
            .pickerStyle(.segmented)

            Toggle("Favorite", isOn: $isFavorite)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(project == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 400)
        .onAppear {
            if let project {
                name = project.name
                color = project.color
                parentID = project.parentID
                isFavorite = project.isFavorite
                viewStyle = project.viewStyle
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let project {
            project.name = trimmed
            project.color = color
            project.parentID = parentID
            project.isFavorite = isFavorite
            project.viewStyle = viewStyle
            store.scheduleSave()
        } else {
            let p = store.addProject(name: trimmed, color: color, parentID: parentID, viewStyle: viewStyle)
            p.isFavorite = isFavorite
            store.scheduleSave()
        }
        dismiss()
    }
}

/// Row of selectable color dots for the Todoist palette.
struct ColorPickerRow: View {
    @Binding var selection: ItemColor

    private let columns = [GridItem(.adaptive(minimum: 26))]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ItemColor.allCases, id: \.self) { c in
                Button {
                    selection = c
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(c))
                            .frame(width: 20, height: 20)
                        if selection == c {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(c.displayName)
            }
        }
    }
}
