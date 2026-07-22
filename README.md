# Todone

A full-featured, native macOS clone of the Todoist Mac app. SwiftUI + an
observable object graph persisted as a local JSON document. No accounts, no
sync — your data stays in `~/Library/Application Support/Todone/todone.json`.

![status](https://img.shields.io/badge/tests-86%20passing-brightgreen)

## Features

- **Tasks** — priorities (P1–P4), descriptions, subtasks (nested), labels,
  reminders, drag-reorder
- **Projects** — colors, nesting, favorites, archive, sections, list *and*
  kanban board views
- **Views** — Inbox, Today (with overdue + "reschedule all"), Upcoming
  (date-grouped with month strip), per-label and per-filter lists
- **Natural-language quick add** — `Pay rent tomorrow 5pm p1 #Finance /Bills
  @home every month` parses date, time, priority, project, section, labels,
  and recurrence live, with token chips
- **Recurring tasks** — `every day`, `every 2 weeks`, `every mon, fri`,
  `every workday`, `every month on the 15th`, strict `every!` variants
- **Filters** — Todoist-style query language: `today & p1`,
  `(#Work | @waiting) & 7 days`, `date before: aug 1`, `search: report`,
  with live validation and match counts
- **Search** — ⌘K command palette over tasks and projects
- **Karma** — points, levels (Beginner → Enlightened), daily/weekly goals,
  streaks, vacation mode, 4-week completion chart
- **Activity log** — grouped by day, filterable by event type
- **Notifications** — reminders at/before due time, dock badge with today count
- **Themes** — 10 accent themes, light/dark/system
- **Keyboard-first** — `q` quick add, `/` search, `t`/`u`/`i` view switching,
  `1–4` priority, `e` complete, global ⌥Space quick add from any app

## Building

Requires macOS 14+ and Swift 6 (Command Line Tools are enough — no Xcode needed).

```bash
swift test              # run the 86-test suite
Scripts/build-app.sh    # build → build/Todone.app
open build/Todone.app
```

## Architecture

- `Sources/TodoneKit` — platform-independent core: models, `AppStore`
  (object graph + atomic debounced JSON persistence), and pure engines
  (`QuickAddParser`, `NLDateParser`, `RecurrenceRule`, `FilterEngine`,
  `KarmaEngine`), all unit-tested
- `Sources/Todone` — the SwiftUI app
- `docs/superpowers/specs/` — design spec

Todone is an unaffiliated clone built for personal use; it uses no Todoist
assets or trademarks.
