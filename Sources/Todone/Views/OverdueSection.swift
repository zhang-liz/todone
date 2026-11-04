import SwiftUI
import TodoneKit

/// The Overdue header and rows on Today and Upcoming. A long list folds to its
/// header so upcoming work stays in view.
struct OverdueSection: View {
    @Environment(AppStore.self) private var store
    @Environment(AppModel.self) private var model

    let overdue: [TodoTask]
    let headerColor: Color

    var body: some View {
        if !overdue.isEmpty {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            ForEach(model.shownOverdue(overdue)) { task in
                TaskRowView(task: task, showsProject: true)
                    .draggable(task.id.uuidString)
                    .padding(.horizontal, 20)
                Divider().padding(.leading, 48)
            }
        }
    }

    private var header: some View {
        HStack {
            if OverdueFold.canFold(count: overdue.count) {
                Button {
                    model.toggleOverdue(overdue)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.overdueExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 12)
                        title
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.overdueExpanded ? "Hide overdue tasks" : "Show overdue tasks")
            } else {
                title
            }
            Spacer()
            Button("Reschedule all to Today") {
                // One undo step: the undo stack holds 50, so a step per task
                // would make a long list impossible to fully undo.
                store.asSingleUndoStep {
                    for t in overdue {
                        store.updateTask(t) { task in
                            task.dueDate = Calendar.current.startOfDay(for: Date())
                            task.hasDueTime = false
                        }
                    }
                }
            }
            .font(.callout)
        }
    }

    private var title: some View {
        HStack(spacing: 6) {
            Text("Overdue").font(.headline).foregroundStyle(headerColor)
            Text("\(overdue.count)").font(.callout).foregroundStyle(.secondary)
        }
    }
}
