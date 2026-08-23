# Todone

A full-featured, native macOS clone of the Todoist Mac app. SwiftUI + an
observable object graph persisted as a local JSON document. No accounts and no
sync, so your data stays in `~/Library/Application Support/Todone/todone.json`.

[![Download for macOS](https://img.shields.io/badge/Download%20for%20macOS-.dmg-0A84FF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/zhang-liz/todone/releases/latest)

![status](https://img.shields.io/badge/tests-143%20passing-brightgreen)
[![release](https://img.shields.io/github/v/release/zhang-liz/todone?display_name=tag)](https://github.com/zhang-liz/todone/releases/latest)

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

## Install

Open the disk image and drag Todone to Applications. Requires macOS 14 or later.

The app is signed ad-hoc, not notarized, so macOS blocks it the first time you
open it. To get past that, right-click Todone in Applications, choose **Open**,
then click **Open** in the dialog. You only do this once.

Tasks are stored in `~/Library/Application Support/Todone/todone.json`. There
is no sync, so a fresh install on another Mac starts empty. To bring your tasks
with you, copy that file across.

### Build from source

Requires Swift 6. Command Line Tools are enough, so you do not need Xcode.

```bash
git clone https://github.com/zhang-liz/todone.git
cd todone
Scripts/build-app.sh
cp -r build/Todone.app /Applications/
```

## Development

```bash
swift test              # 143 tests
Scripts/build-app.sh    # build -> build/Todone.app
open build/Todone.app
```

## Architecture

- `Sources/TodoneKit` — platform-independent core: models, `AppStore`
  (object graph + atomic debounced JSON persistence), and pure engines
  (`QuickAddParser`, `NLDateParser`, `RecurrenceRule`, `FilterEngine`,
  `KarmaEngine`), all unit-tested
- `Sources/Todone` — the SwiftUI app
- `docs/superpowers/specs/` — design spec
- `docs/STATUS.md` — what is built, test coverage, and where the app
  deviates from the spec

Todone is an unaffiliated clone built for personal use; it uses no Todoist
assets or trademarks.
