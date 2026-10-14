# TaskWidget

A menu-bar task manager for macOS with a LockDay-style desktop widget, a calendar, weekly
reports and a global quick-capture hotkey. Data lives in a small local Rust server
([`backend/`](backend/README.md)) on `127.0.0.1:3220`.

- **Quick capture** — press **⌥Space** anywhere, type `Fix bug #wms !high besok`, press ↵
- **Desktop widget** — small / medium / large: check off, snooze, switch lists, page through, add
- **App window** — smart lists, projects, editor, search, calendar, weekly reports
- **Reminders** — a daily summary of everything open (with deadlines, including tasks without a due date); due and overdue tasks repeat until done
- **Menu bar** — today's tasks, new task, open window; the Dock icon only shows while the window is open

## Requirements

| | |
|---|---|
| macOS | 15 or later (the widget itself runs on 14+) |
| Xcode | 26 or later (the KeyboardShortcuts package needs Swift 6.2 tools) |
| Rust | stable, via [rustup](https://rustup.rs) |
| Apple ID | any free Apple ID, for signing the app and widget in Xcode |

## Setup (first time)

### 1. Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
```

Open a **new terminal** afterwards so `cargo` is on your `PATH`, then check with `cargo --version`.

### 2. Start the backend

From the repo root:

```bash
./backend/scripts/install-launch-agent.sh
```

This builds the server, installs it to `~/Library/Application Support/TaskWidget/bin/`, and
registers a LaunchAgent so it **starts at every login and restarts if it crashes**. It ends with
`✓ taskwidget-server is running on http://127.0.0.1:3220`. You can check it at any time:

```bash
curl -s http://127.0.0.1:3220/api/health
```

The database is `~/Library/Application Support/TaskWidget/tasks.db`; logs go to
`~/Library/Logs/TaskWidget/server.log`.

### 3. (Optional) Import existing tasks

If you have tasks on another server with the same API (e.g. the old multi-agent backend on
port 3210), copy them over once. IDs, completion state and dates are kept; tasks that already
exist are skipped, so it's safe to run again.

```bash
"$HOME/Library/Application Support/TaskWidget/bin/taskwidget-server" import http://localhost:3210
```

### 4. Configure signing in Xcode

1. Open `TaskWidget.xcodeproj`. Xcode fetches the `KeyboardShortcuts` package automatically.
2. Select the **TaskWidget** project → **Signing & Capabilities**.
3. For **both** targets, **TaskWidget** and **TaskWidgetExtension**, choose your **Team**
   (*Add Account…* if it's empty — a free Apple ID works).

> **Required for an interactive widget.** macOS only runs widget buttons and checkboxes for
> extensions signed with a Team ID. An ad-hoc build ("Sign to Run Locally") shows the widget, but
> every click just opens the app. Check with
> `codesign -dvv /Applications/TaskWidget.app 2>&1 | grep TeamIdentifier` — it must not say `not set`.

### 5. Build and install to /Applications

In Xcode: pick the **TaskWidget** scheme → **Product → Build** (⌘B) → **Product → Show Build
Folder in Finder** → `Products/Debug/` → drag **TaskWidget.app** into **Applications**
(replace the old copy if asked).

Or from the terminal:

```bash
xcodebuild -project TaskWidget.xcodeproj -scheme TaskWidget -configuration Release -derivedDataPath build build
```

```bash
cp -R build/Build/Products/Release/TaskWidget.app /Applications/
```

Keep only **one** copy of `TaskWidget.app` on your Mac; older copies elsewhere can hijack the
widget.

### 6. First launch

Open **TaskWidget** from Applications. **No window appears** — look for the ☑︎ icon in the menu
bar. From that menu:

- **Open TaskWidget** (⌘O) — the main window
- **Settings…** (⌘,) — turn on **Open at login** so the menu bar app, hotkey and reminders are
  ready after every login

macOS asks for permission to send notifications on first launch — click **Allow**.

### 7. Put the widget on the desktop

1. Right-click an empty spot on the desktop → **Edit Widgets…**
2. Search **TaskWidget**, pick Small, Medium or Large and drag it onto the desktop → **Done**.
3. **System Settings → Desktop & Dock → Widgets**: enable **Show Widgets: On Desktop** and set
   **Widget style: Full-color** (otherwise it turns grey when the desktop isn't focused).

You only do this once — macOS keeps the widget on the desktop across logins.

**What you can click in the widget**

| | Small | Medium | Large |
|---|---|---|---|
| ○ check a task off (today's done tasks stay struck through — click again to undo) | ✓ | ✓ | ✓ |
| Switch list: Today · Upcoming · Important · Someday | tap the title | tab pills | tab pills |
| ‹ 1/2 › page through long lists | ✓ | ✓ | ✓ |
| ↪ snooze a today/overdue task to tomorrow | | ✓ | ✓ |
| ＋ open quick capture | ✓ | ✓ | ✓ |
| Tap a day in the next-7-days strip to see that day | | | ✓ |
| Today's progress ring (done / due) | | ✓ | ✓ |
| ↗ open the app (clicks on empty space do nothing) | ✓ | ✓ | ✓ |

Each widget size remembers its own list and page.

### 8. Try quick capture

Press **⌥Space** from any app, type a task, press **↵**. That's it.

## Quick capture

| Key | Action |
|---|---|
| ↵ | Add and close |
| ⇧↵ | Add and keep the panel open for the next task |
| ⇥ | Switch Task ↔ Note (when no autocomplete suggestion is showing) |
| ⌘T / ⌘N | Switch to Task / Note |
| Esc / click outside | Close |

Typing `//` at the start also saves the text as a note.

**Autocomplete** appears while you type: `#` lists your projects, `!` the priorities, `@` or the
start of a date word (`bes…`, `fri…`, `jum…`) the dates with what they resolve to, and the start of
a title earlier tasks — picking one fills in its project and priority too. **⇥** accepts the
highlighted suggestion, **↑/↓** choose another (then **↵** accepts it), **Esc** hides the list.

Shortcuts you can type anywhere in the text (they're removed from the title). Every task can
have two optional dates: the **do date** (the day you plan to work on it) and the **due date**
(the deadline). A date on its own sets the do date; put **`due`**, **`deadline`**, **`dl`**,
**`by`** or **`sebelum`** in front of it to set the due date — `besok due jumat` means *work on
it tomorrow, due Friday*.

| Type | Means |
|---|---|
| `#wms` | Project *wms* (matches existing projects case-insensitively; new names create a project) |
| `!high` `!h` `!!!` `!tinggi` | High priority |
| `!medium` `!m` `!!` `!sedang` | Medium priority |
| `!low` `!l` `!` `!rendah` | Low priority |
| `today` `hari ini` · `tomorrow` `besok` · `lusa` | Relative day |
| `friday` `jumat` · `next friday` · `hari minggu` | Weekday (next occurrence; today counts) |
| `@fri` `@sun` `@minggu` | Short or ambiguous weekdays need `@` |
| `next week` `minggu depan` · `this weekend` `akhir pekan` | Next week's first day · Saturday |
| `in 3 days` `3 hari lagi` `dalam 3 hari` | Days from today |
| `12/10` `12/10/2026` `2026-10-12` `25 des` `oct 20` | Exact date (day first; past dates roll to next year) |

Example: `Bayar listrik #Personal !! besok dl 3 hari lagi` → *Bayar listrik*, project Personal,
medium, do tomorrow, due in 3 days. Without `#project` the task goes to the project you used last.

**Change the hotkey:** menu bar → **Settings… → Quick Capture** → click the field and press
a new combination (it warns about conflicts). **Reset to ⌥Space** restores the default. If
Raycast or Alfred already uses ⌥Space, pick something else here.

## Reminders

**Daily summary** — every day at **08:00** a notification lists everything still open, each with
when to do it and when it's due: overdue (`overdue 2 days`), due today, planned for today
(`do today · due Fri (in 3 days)`), coming up this week, and tasks **without any date**
(`no deadline`). Both dates are optional; undated tasks show up in the summary every day until
you complete them.

**Repeats until done** — tasks that are **due today or overdue** are repeated every **hour**
(after the summary) until **21:00**, and again the next day, until you mark them done. A
reminder about a single task has **Mark as Done**; every reminder has **Snooze 1 Hour**.
Completing the tasks clears the remaining repeats and removes the ones on screen.

If the app wasn't running at summary time (Mac off, logged in late), the summary is sent as soon
as it starts, once per day.

Settings → **Reminders**: turn them off, change the summary time, the repeat interval
(15 min – 3 h) and the end time, and **Send test notification**. If macOS notifications are off
for TaskWidget, the same section links to System Settings.

## Using the app

- **Sidebar** — *Today, Upcoming, Important, Someday, All Tasks, Completed*, **Calendar**,
  **Notes**, the last six **Weekly Reports**, and your **Projects**.
- **Two dates** — **Do on** (▶, the day you'll work on it) and **Due** (🏁, the deadline), both
  optional. *Today* shows what's planned for today or earlier and what's due; *Upcoming* groups
  tasks by their do day (or due day when there's no do date); *Someday* has tasks with neither.
- **Add** — the *Add a task…* bar at the top of each list, with **Do** and **Due** chips;
  defaults follow the list (Today → do today, Upcoming → do tomorrow, Important → high
  priority, a project → that project).
- **Edit** — click a task: the editor docks on the right (or opens as a sheet in a narrow
  window). Change title, notes, project, priority, do date, due date; **⌘S** saves, **Esc** closes.
- **Quick edits** — right-click a task for priority, do date, due date, project, done, or delete.
  Hover shows calendar / edit / delete buttons.
- **Calendar** — month grid with tasks on their do day (or due day); click a day to see and plan
  tasks for it; **drag a task onto another day** to move its do date (or its due date when it has
  no do date).
- **Notes** — plain-text notes, newest first, grouped by Today / Yesterday / Previous 7 Days /
  Earlier. Write in the box at the top (**↵** saves, **⌥↵** new line; the first line is the
  title). Click a note to edit it in place (**Esc** cancels); hover or right-click to copy,
  edit or delete. The toolbar search field searches notes while you're on this page; **⌘N**
  jumps to the note box.
- **Weekly report** — completed (vs last week), created, completion rate of tasks due that week,
  overdue, a daily chart, breakdowns by project and priority, and the tasks behind them.
- **Shortcuts** — ⌘N new task · ⌘R refresh · ⌘, settings · search field in the toolbar.

Every change refreshes the desktop widget immediately.

## After pulling new code

| Changed | Do this |
|---|---|
| `backend/` | `./backend/scripts/install-launch-agent.sh` (rebuilds and restarts the server; database migrations run automatically) |
| App or widget | Quit TaskWidget (menu bar → Quit), rebuild (step 5), replace the copy in /Applications, open it again |
| Widget still shows old content | `pkill -f TaskWidgetExtension` — macOS restarts the widget with the new build |

## Troubleshooting

| Problem | Fix |
|---|---|
| Widget/app says **Backend offline** | `curl -s http://127.0.0.1:3220/api/health`; if it fails, `launchctl kickstart -k gui/$(id -u)/com.taskwidget.server` and check `~/Library/Logs/TaskWidget/server.log` |
| Clicking anything in the widget just opens the app | The build isn't signed with a Team (step 4). Set it for both targets, rebuild, replace the app, `pkill -f TaskWidgetExtension` |
| Widget shows *Failed to load widget… error 5* | Set the **Team** on both targets (step 4), clean (⇧⌘K) and rebuild |
| TaskWidget missing in **Edit Widgets** | Open the app from /Applications once, then log out and back in |
| Widget still uses an old server/port | Remove stray copies of `TaskWidget.app`, then `pkill -f TaskWidgetExtension` |
| No morning notification | Settings → Daily Reminder → *Send test notification*; if nothing shows, allow TaskWidget in **System Settings → Notifications** |
| ⌥Space does nothing | Is the ☑︎ icon in the menu bar? If not, open the app. Otherwise another app owns the shortcut — change it in Settings |
| `launchctl bootstrap` *error 5* | Run the install script again; it waits for the old service to stop |
| Sidebar/columns look squashed after an update | Quit the app, run `defaults delete com.multiagent.taskwidget` (only window sizes are reset), reopen |

## Uninstall

```bash
./backend/scripts/uninstall-launch-agent.sh
```

Then quit TaskWidget and delete `/Applications/TaskWidget.app`. The database stays in
`~/Library/Application Support/TaskWidget/` until you delete that folder.

## Project layout

```
TaskWidget/                 macOS app (menu bar, window, quick capture)
├── App/                    AppDelegate (hotkey, lifecycle, Dock), menu bar
├── Notifications/          morning reminder planning + scheduling
├── Assets.xcassets         app icon (regenerate: scripts/render_app_icon.swift)
├── QuickCapture/           floating panel + natural-language parser
├── Store/TaskStore.swift   shared, optimistic state
├── Models/                 Task, sidebar lists, weekly report maths
├── Services/APIClient.swift
└── Views/                  sidebar, lists, editor, calendar, reports
TaskWidgetExtension/        desktop widget (WidgetKit, interactive)
Shared/                     code used by both: constants, palette, grouping
backend/                    Rust API server — see backend/README.md
```

Backend development: `cd backend && cargo test && cargo clippy --all-targets -- -D warnings`.
API reference: [backend/README.md](backend/README.md).

## License

Private project.
