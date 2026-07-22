import SwiftUI
import TodoneKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gear") }
            ThemeSettings()
                .tabItem { Label("Theme", systemImage: "paintpalette") }
            KarmaSettings()
                .tabItem { Label("Karma", systemImage: "chart.line.uptrend.xyaxis") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 460, height: 340)
    }
}

private struct GeneralSettings: View {
    @AppStorage("startView") private var startView = "today"
    @AppStorage("badgeCount") private var badgeCount = true

    var body: some View {
        Form {
            Picker("Start view", selection: $startView) {
                Text("Today").tag("today")
                Text("Inbox").tag("inbox")
                Text("Upcoming").tag("upcoming")
            }
            Toggle("Show today count in Dock badge", isOn: $badgeCount)
                .onChange(of: badgeCount) {
                    NotificationScheduler.shared.refreshBadge()
                }
        }
        .padding(20)
    }
}

private struct ThemeSettings: View {
    @AppStorage("themeID") private var themeID = "todoneRed"
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue

    private let columns = [GridItem(.adaptive(minimum: 92))]

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppearanceSetting.allCases, id: \.rawValue) { a in
                    Text(a.displayName).tag(a.rawValue)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppTheme.all) { theme in
                    Button {
                        themeID = theme.id
                    } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.accent)
                                .frame(height: 34)
                                .overlay {
                                    if themeID == theme.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .fontWeight(.bold)
                                    }
                                }
                            Text(theme.name)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
    }
}

private struct KarmaSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Toggle("Karma enabled", isOn: Binding(
                get: { store.karma.karmaEnabled },
                set: { store.karma.karmaEnabled = $0 }
            ))
            Toggle("Vacation mode (freeze streaks)", isOn: Binding(
                get: { store.karma.vacationMode },
                set: { store.karma.vacationMode = $0 }
            ))
            Stepper("Daily goal: \(store.karma.dailyGoal) tasks", value: Binding(
                get: { store.karma.dailyGoal },
                set: { store.karma.dailyGoal = max(1, $0) }
            ), in: 1...50)
            Stepper("Weekly goal: \(store.karma.weeklyGoal) tasks", value: Binding(
                get: { store.karma.weeklyGoal },
                set: { store.karma.weeklyGoal = max(1, $0) }
            ), in: 1...300)
        }
        .padding(20)
    }
}

private struct DataSettings: View {
    @Environment(AppStore.self) private var store
    @State private var showEraseConfirm = false
    @State private var exportResult: String?

    var body: some View {
        Form {
            Button("Export data as JSON…") { exportData() }
            if let exportResult {
                Text(exportResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Erase all data…", role: .destructive) {
                showEraseConfirm = true
            }
            .confirmationDialog("Erase everything? This can't be undone.",
                                isPresented: $showEraseConfirm) {
                Button("Erase all data", role: .destructive) {
                    store.eraseAll()
                }
            }
        }
        .padding(20)
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "todone-export.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportJSON()
            try data.write(to: url)
            exportResult = "Exported to \(url.lastPathComponent)"
        } catch {
            exportResult = "Export failed: \(error.localizedDescription)"
        }
    }
}
