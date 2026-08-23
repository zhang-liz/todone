import SwiftUI
import TodoneKit

/// Flushes the debounced store save on quit so ⌘Q within the debounce window
/// can't drop mutations.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var store: AppStore?

    func applicationWillTerminate(_ notification: Notification) {
        Self.store?.saveNow()
    }
}

@main
struct TodoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore
    @State private var model = AppModel()
    @AppStorage("themeID") private var themeID = "todoneRed"
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue

    init() {
        let s = AppStore()
        s.load(from: AppStore.defaultStoreURL())
        if CommandLine.arguments.contains("--sample-data") || !UserDefaults.standard.bool(forKey: "didFirstRun") {
            SampleData.installIfEmpty(into: s)
            UserDefaults.standard.set(true, forKey: "didFirstRun")
        }
        _store = State(initialValue: s)
        AppDelegate.store = s
        NotificationScheduler.shared.attach(store: s)
    }

    var theme: AppTheme { AppTheme.theme(id: themeID) }
    var appearance: AppearanceSetting { AppearanceSetting(rawValue: appearanceRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(model)
                .environment(\.appTheme, theme)
                .tint(theme.accent)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 700)
        .commands { AppCommands(store: store, model: model) }

        Settings {
            SettingsView()
                .environment(store)
                .environment(\.appTheme, theme)
                .tint(theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

// MARK: - Theme environment

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.all[0]
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Menu commands

struct AppCommands: Commands {
    let store: AppStore
    let model: AppModel

    var body: some Commands {
        // Replaces rather than follows .newItem: WindowGroup synthesises a
        // "New Window" item that also claims ⌘N, and macOS gives the shortcut
        // to whichever comes first, leaving Add Task unreachable.
        CommandGroup(replacing: .newItem) {
            Button("Add Task") { model.showQuickAdd = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Search") { model.showSearch = true }
                .keyboardShortcut("k", modifiers: .command)
        }

        CommandMenu("Go") {
            Button("Inbox") { model.select(.inbox) }
                .keyboardShortcut("0", modifiers: .command)
            Button("Today") { model.select(.today) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Upcoming") { model.select(.upcoming) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Filters & Labels") { model.select(.filtersAndLabels) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Activity") { model.select(.activity) }
                .keyboardShortcut("4", modifiers: .command)
        }

        CommandMenu("Task") {
            Button("Complete") {
                if let id = model.selectedTaskID, let t = store.task(id) {
                    store.complete(t)
                    model.selectedTaskID = nil
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.selectedTaskID == nil)

            Divider()

            ForEach(Priority.allCases, id: \.rawValue) { p in
                Button("Priority \(p.rawValue)") {
                    if let id = model.selectedTaskID, let t = store.task(id) {
                        store.updateTask(t) { $0.priority = p }
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(p.rawValue)")), modifiers: .option)
                .disabled(model.selectedTaskID == nil)
            }

            Divider()

            Button("Due Today") { reschedule(to: Date()) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model.selectedTaskID == nil)
            Button("Due Tomorrow") {
                reschedule(to: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(model.selectedTaskID == nil)
            Button("Remove Due Date") { removeDueDate() }
                .disabled(model.selectedTaskID == nil)

            Divider()

            Button("Delete Task") {
                if let id = model.selectedTaskID, let t = store.task(id) {
                    store.deleteTask(t)
                    model.selectedTaskID = nil
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedTaskID == nil)
        }
    }

    private func reschedule(to date: Date) {
        guard let id = model.selectedTaskID, let t = store.task(id) else { return }
        store.updateTask(t) {
            $0.dueDate = Calendar.current.startOfDay(for: date)
            $0.hasDueTime = false
        }
    }

    private func removeDueDate() {
        guard let id = model.selectedTaskID, let t = store.task(id) else { return }
        store.updateTask(t) {
            $0.dueDate = nil
            $0.hasDueTime = false
            $0.recurrence = nil
        }
    }
}
