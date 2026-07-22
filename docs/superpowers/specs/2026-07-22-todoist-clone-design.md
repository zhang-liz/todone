# Todoist Clone ("Todone") — Design Spec

**Date:** 2026-07-22
**Status:** Approved
**Target:** Native macOS app, macOS 14+, SwiftUI + SwiftData, local-only data (no accounts, no sync, no collaboration).

## Goal

A full-featured clone of the Todoist Mac app for a single local user: tasks, projects, sections, subtasks, priorities, due dates with natural-language parsing, recurring tasks, labels, filters, search, board view, activity log, karma/gamification, themes, reminders/notifications, and keyboard-first workflows.

Out of scope: accounts, multi-device sync, collaboration/sharing, integrations, email/calendar feeds, mobile.

## Naming

App name "Todone". No Todoist trademark in bundle ID, app name, or UI copy. Visual style may resemble Todoist but assets (icons, logos) are original.

## Architecture

- **UI:** SwiftUI, `NavigationSplitView` shell.
- **Persistence:** SwiftData (`@Model` classes), single local store.
- **Pattern:** Observable models + plain Swift service types (parser, filter engine, recurrence engine, karma calculator). No heavyweight MVVM layer.
- **Heavy logic lives in pure, testable Swift modules** independent of SwiftUI: `QuickAddParser`, `FilterEngine`, `RecurrenceEngine`, `KarmaEngine`.

## 1. Data Model (SwiftData)

- **Project**: `name`, `color`, `isFavorite`, `isInbox` (exactly one Inbox, undeletable), `viewStyle` (list | board), `sortOrder`, `parent: Project?` (nesting), `isArchived`.
- **Section**: `name`, `sortOrder`, belongs to Project.
- **Task**: `title`, `details` (description), `priority` (p1–p4; p4 = none), `dueDate: Date?`, `hasDueTime: Bool`, `recurrenceRule: String?` (serialized RecurrenceRule), `sortOrder`, `completedAt: Date?`, `createdAt`, `project`, `section?`, `parent: Task?` (subtasks, arbitrary depth; UI indents up to 4 levels), labels (many-to-many).
- **Label**: `name` (unique), `color`, `isFavorite`.
- **FilterQuery**: `name`, `query` (string in filter grammar), `color`, `isFavorite`.
- **Reminder**: either absolute `Date` or relative offset (minutes before due time), belongs to Task.
- **ActivityEvent**: `type` (added | completed | uncompleted | updated | deleted), `timestamp`, `taskTitle` snapshot, `projectName` snapshot, optional task reference.
- **KarmaState**: singleton — `points`, `currentStreakDays`, `maxStreakDays`, `weeklyStreak`, `dailyGoal` (default 5), `weeklyGoal` (default 25), `vacationMode`, `karmaEnabled`. Recomputed incrementally from activity; daily completion counts cached in a `DailyStat` model (`date`, `completedCount`, `addedCount`).

### RecurrenceRule

Custom struct serialized to a compact string. Supports: every day / week / month / year, every N units, specific weekdays ("every mon, fri"), "every workday", "every month on the Nth", and strict variants. Matching Todoist semantics: plain `every` advances from the current due date; `every!` advances from the completion date. Completing a recurring task sets the next due date instead of marking it completed; an ActivityEvent `completed` is still logged and karma counts it.

Deleting or "ending" recurrence available in task detail.

## 2. App Shell

- `NavigationSplitView`: sidebar + detail column.
- **Sidebar:** Inbox, Today (with count badge), Upcoming, Filters & Labels, then Favorites section (favorited projects/labels/filters), then Projects tree (disclosure groups for nesting), Add-project button. Context menus: edit, favorite, archive, delete, add section.
- **Task detail:** trailing inspector panel (Mac-native alternative to Todoist's modal) showing title, description, project/section picker, due date picker with NL field, priority, labels, reminders, subtasks list, comments-free (no comments — collaboration feature; activity shown instead).
- **Menu bar menus:** File (Add Task ⌘N, Add Project ⇧⌘N, Quick Add ⌃Space), Edit (standard + Undo), View (Inbox ⌘0, Today ⌘1, Upcoming ⌘2, toggle sidebar, list/board toggle), Task (Complete ⌘⏎, Priority 1–4 ⌥1–⌥4, Reschedule), Help. View-navigation owns ⌘1/⌘2; priorities use ⌥ to avoid conflict.
- **Single-key shortcuts** (when list focused, no text field): `q` quick add, `a` add task inline, `1`–`4` set priority of selected, `t` today, `u` upcoming, `⌫` delete, `e` archive/complete, arrows/j/k navigate.
- **Global Quick Add:** borderless floating `NSPanel` summoned by system-wide hotkey (default ⌥Space, configurable) even when app in background. Contains Quick Add field.
- **Settings window (⌘,):** General (start view, badge count), Quick Add hotkey, Theme, Karma goals & vacation mode, Data (export JSON, erase all).

## 3. Views

- **Project list view:** grouped by section; inline add-task row at each section bottom; checkbox with fill-then-fade completion animation; hover actions (edit, schedule, more); drag to reorder within/between sections; header menu: sort (manual, date, priority, name), group-by, show completed toggle.
- **Board view:** horizontal scrolling columns = sections; task cards; drag between columns; add card at column bottom; column add/rename/reorder.
- **Today:** two groups — Overdue (with "Reschedule all → Today" button) and Today. Tasks show project breadcrumb.
- **Upcoming:** vertically scrolling date-grouped list (day headers, "Add task" per day), horizontal month strip at top for jumping; overdue block pinned at top.
- **Filters & Labels view:** two lists; tapping opens task list driven by FilterEngine (filters) or label match (labels). Filter CRUD with live query validation + preview count.
- **Search (⌘F or ⌘K):** command-palette-style overlay; searches task titles, descriptions, project names, labels; sections for Tasks / Projects; Enter navigates.
- **Completed / Activity:** per-project "Show completed" inline; global Activity log view (grouped by day, event icons, filter by project/event type); uncomplete restores task.

## 4. Quick Add Natural-Language Parsing

Own parser, no dependencies. Input tokens recognized live while typing, rendered as colored highlights; clicking a highlighted token or pressing ⌫ over it removes just that token's effect.

- **Dates:** `today`, `tomorrow`, `tod`, `tom`, weekday names ("monday", "next monday"), `jul 30`, `30 jul`, `7/30`, `in 3 days`, `in 2 weeks`, times ("3pm", "15:00", "at 3pm"), date+time combos.
- **Recurrence:** `every day`, `every 2 weeks`, `every mon, fri`, `every workday`, `every month on the 1st`, `every!` variants.
- **Priority:** `p1`, `p2`, `p3` (`p4`/none default).
- **Project:** `#ProjectName` (autocomplete popup; quoted for spaces: `#"Big Project"`).
- **Section:** `/SectionName` (after a project token).
- **Label:** `@label` (autocomplete; creates label on the fly if new).
- **Escape:** no dedicated escape syntax. `#`/`@`/`/` tokens only trigger at word start; any auto-recognized token can be "un-parsed" by clicking its highlight, returning the text to the plain title.
- Parser returns `ParsedTask { title, dueDate?, hasTime, recurrence?, priority, projectHint?, sectionHint?, labelHints[] }` + token ranges for highlighting.

Quick Add UI used in three places: global panel, in-app quick add (q), inline add rows (dates/priority tokens only parsed there too).

## 5. Filter Query Engine

Parser + evaluator over in-memory task array (dataset is personal-scale; no SQL pushdown needed).

Grammar (Todoist-compatible subset):

```
expr    := or
or      := and ("|" and)*
and     := unary ("&" unary)*
unary   := "!" unary | "(" expr ")" | term
term    := "today" | "tomorrow" | "overdue" | "no date" | "no time"
         | "p1".."p4" | "no priority"
         | "#" project | "##" project-with-subprojects | "/" section
         | "@" label | "no label"
         | "N days" (next N days) | "date : X" | "date before: X" | "date after: X"
         | "created before: X" | "created after: X"
         | "search: text" | "subtask" | "!subtask" | "recurring"
```

Date arguments reuse the Quick Add date parser. Invalid queries surface inline errors in filter editor. Same engine evaluates Today/Upcoming groupings where convenient.

## 6. Karma

- Points: +5 per task completed, +10 bonus when daily goal met, +25 bonus when weekly goal met. No negative points (skip Todoist's overdue penalty — keeps engine simple).
- Levels by cumulative points: Beginner 0, Novice 500, Intermediate 2500, Professional 5000, Expert 7500, Master 10000, Grandmaster 20000, Enlightened 50000.
- Daily/weekly goal progress + current/max streaks; vacation mode freezes streaks; karma can be disabled.
- Profile popover (click avatar/name in toolbar): level, points, streaks, last-4-weeks completion bar chart.

## 7. Theming

- ~10 named accent themes (default "Todone Red"), each with accent color used for: sidebar selection, add buttons, links, toggles, focused rings.
- Appearance: light / dark / system.
- Priority colors constant across themes: p1 red, p2 orange, p3 blue, p4 gray.
- Implementation: `Theme` struct + environment; stored in `AppStorage`.

## 8. Notifications

- `UserNotifications` framework; permission requested on first reminder creation.
- Reminders fire at absolute time or offset before due time; actions on notification: Complete, Snooze 10m.
- App badge = count of today+overdue tasks (toggle in Settings).
- Rescheduling/completing/deleting a task reschedules/cancels its pending notifications.

## 9. Testing

- **Unit tests (XCTest), TDD for pure engines:** QuickAddParser (dates, recurrence, tokens, edge cases), FilterEngine (grammar, precedence, negation, date terms), RecurrenceEngine (next-occurrence math incl. month ends, `every!` vs `every`), KarmaEngine (points, streaks, vacation).
- **Model tests:** SwiftData CRUD, cascade rules (delete project ⇒ tasks; delete parent task ⇒ subtasks), Inbox invariants.
- **UI smoke tests (XCUITest):** launch, add task, complete task, create project, drag not covered (flaky) — manual checklist instead.
- Each milestone ends green: `xcodebuild test` passes, app builds and runs.

## 10. Milestones

1. **M1 Foundation** — Xcode project scaffold, SwiftData models, sidebar shell, Inbox list with add/edit/complete/delete, task detail inspector (basic fields).
2. **M2 Organization** — project & section CRUD, project nesting, drag-reorder, subtasks, priorities, favorites, archive.
3. **M3 Dates** — due date picker + NL date field, Today view, Upcoming view, RecurrenceEngine, reschedule flows, overdue handling.
4. **M4 Quick Add** — QuickAddParser, in-app quick add, global hotkey panel, token highlighting, full keyboard shortcut map.
5. **M5 Labels, Filters, Search** — label CRUD, FilterEngine + filter CRUD/preview, search overlay.
6. **M6 Board & Activity** — board view with drag, completed-tasks view, activity log.
7. **M7 Karma, Notifications, Themes** — KarmaEngine + profile popover, reminders + notifications + badge, theme system, full Settings.
8. **M8 Polish** — animations, empty states, first-run sample data, app icon, performance pass, manual QA checklist.

Each milestone: own implementation plan, small atomic commits, buildable app at end.

## Error Handling Principles

- SwiftData save failures: surface non-blocking toast, log; never silently drop user input.
- Parser failures degrade gracefully: unparsed text stays in title.
- Notification permission denied: reminders UI shows inline notice, app remains functional.
- Store corruption/migration failure: offer JSON export of readable data + reset.

## Risks

- SwiftData maturity (macOS 14): mitigations — keep queries simple, engines in-memory, integration tests around CRUD.
- Global hotkey + floating panel needs AppKit interop (`NSPanel`, Carbon/`CGEvent` hotkey or MASShortcut-style implementation without dependency): isolated in one module.
- Drag & drop across sections/columns in SwiftUI is fiddly: fall back to AppKit-backed list if needed (decide in M2).
