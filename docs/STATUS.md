# Status

Last updated: 2026-08-22. Tracks the [design spec](superpowers/specs/2026-07-22-todoist-clone-design.md) against what is actually built.

## Summary

All 8 milestones are implemented. 186 tests pass. The app builds and runs from a clean clone.

Two deliberate changes from the spec, both listed under [Deviations](#deviations-from-the-spec): persistence uses JSON instead of SwiftData, and there are no UI tests.

## Milestones

| # | Milestone | State | Where |
|---|---|---|---|
| M1 | Foundation: models, sidebar, Inbox, task detail | Done | `Models.swift`, `SidebarView`, `ContentView`, `TaskDetailView` |
| M2 | Organization: projects, sections, nesting, subtasks, drag-reorder | Done | `ProjectView`, `AppStore` |
| M3 | Dates: due dates, Today, Upcoming, recurrence | Done | `NLDateParser`, `RecurrenceRule`, `TodayView`, `UpcomingView` |
| M4 | Quick Add: parser, global hotkey, token chips | Done | `QuickAddParser`, `QuickAddView`, `KeyMonitor` |
| M5 | Labels, filters, search | Done | `FilterEngine`, `FiltersLabelsView`, `SearchView` |
| M6 | Board and activity log | Done | `BoardView`, `ActivityView` |
| M7 | Karma, notifications, themes | Done | `KarmaEngine`, `NotificationScheduler`, `Theme` |
| M8 | Polish: empty states, sample data, app icon | Done | `SampleData`, `Assets/AppIcon.icns` |

## Tests

186 tests, all passing. Run with `swift test`.

| Suite | Tests | Covers |
|---|---|---|
| `AdversarialTests` | 31 | Malformed input, boundary conditions |
| `NLDateParserTests` | 23 | Date phrases, times, relative dates |
| `RegressionTests` | 23 | Previously fixed bugs |
| `AppStoreTests` | 22 | CRUD, cascade deletes, persistence |
| `RecurrenceRuleTests` | 16 | Next-occurrence math, month ends, `every!` |
| `FilterEngineTests` | 14 | Query grammar, precedence, negation |
| `QuickAddParserTests` | 11 | Token recognition and ranges |
| `ScaleTests` | 1 | 5,000 tasks through save, load, and filter |

## Deviations from the spec

**JSON instead of SwiftData.** The spec called for SwiftData. The app stores everything in one JSON file at `~/Library/Application Support/Todone/todone.json`, written atomically and debounced. This removed the SwiftData maturity risk the spec flagged, and it keeps the engines testable without a database. A corrupt store is backed up rather than discarded (`RegressionTests.corruptStoreIsBackedUpNotDiscarded`).

**No UI tests.** The spec planned XCUITest smoke tests. There are none. The project builds through SwiftPM rather than an Xcode project, which XCUITest requires. Engine and store logic is covered by the 186 unit tests; view code is not covered.

**SwiftPM, not an Xcode project.** `Scripts/build-app.sh` assembles the `.app` bundle from the SwiftPM binary. Command Line Tools are enough to build, and Xcode is not needed.

## Not built

- Sync or accounts. Data is local to one machine and does not move between devices.
- Notarization. The app is ad-hoc signed, so Gatekeeper warns on first launch.
- Task comments, file attachments, and shared projects.
