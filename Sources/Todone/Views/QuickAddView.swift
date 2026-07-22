import SwiftUI
import TodoneKit

/// The quick-add sheet: one smart text field with live token preview.
struct QuickAddView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var text = ""
    @State private var description = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Task name — try \"Call mom tomorrow 5pm p2 #Personal @phone\"",
                      text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit(submit)

            TextField("Description", text: $description)
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)

            QuickAddTokenPreview(text: text)

            Divider()

            HStack {
                Text(destinationText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Add task") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 560)
        .onAppear { focused = true }
    }

    private var destinationText: String {
        let parsed = QuickAddParser().parse(text)
        if let name = parsed.projectName {
            return "→ #\(name)" + (parsed.sectionName.map { " / \($0)" } ?? "")
        }
        return "→ Inbox"
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var parsed = QuickAddParser().parse(trimmed)
        if parsed.title.isEmpty { parsed.title = trimmed }
        let task = store.addTask(from: parsed)
        if !description.isEmpty {
            store.updateTask(task) { $0.details = description }
        }
        text = ""
        description = ""
        dismiss()
    }
}
