# TaskWidget

A menu-bar task manager for macOS with a LockDay-style desktop widget, a calendar, weekly
reports and a global quick-capture hotkey. Data lives in a small local Rust server
([`backend/`](backend/README.md)) on `127.0.0.1:3220`.

- **Quick capture** — press **⌥Space** anywhere, type `Fix bug #wms !high besok`, press ↵
- **Desktop widget** — small / medium / large, check tasks off right on the desktop
- **App window** — smart lists, projects, editor, search, calendar, weekly reports
- **Menu bar** — today's tasks, new task, open window; no Dock icon

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
   (*Add Account…* if it's empty). Without a team the widget may refuse to load.

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
- **Settings…** (⌘,) — turn on **Open at login** so the menu bar app and hotkey are ready after
  every login

### 7. Put the widget on the desktop

1. Right-click an empty spot on the desktop → **Edit Widgets…**
2. Search **TaskWidget**, pick Small, Medium or Large and drag it onto the desktop → **Done**.
3. **System Settings → Desktop & Dock → Widgets**: enable **Show Widgets: On Desktop** and set
   **Widget style: Full-color** (otherwise it turns grey when the desktop isn't focused).

You only do this once — macOS keeps the widget on the desktop across logins.

### 8. Try quick capture

Press **⌥Space** from any app, type a task, press **↵**. That's it.

## Quick capture

| Key | Action |
|---|---|
| ↵ | Add and close |
| ⇧↵ | Add and keep the panel open for the next task |
| Esc / click outside | Close |

Shortcuts you can type anywhere in the text (they're removed from the title):

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

Example: `Bayar listrik #Personal !! 3 hari lagi` → *Bayar listrik*, project Personal, medium,
due in 3 days. Without `#project` the task goes to the project you used last.

**Change the hotkey:** menu bar → **Settings… → Quick Capture** → click the field and press
a new combination (it warns about conflicts). **Reset to ⌥Space** restores the default. If
Raycast or Alfred already uses ⌥Space, pick something else here.

## Using the app

- **Sidebar** — *Today, Upcoming, Important, Someday, All Tasks, Completed*, **Calendar**, the
  last six **Weekly Reports**, and your **Projects**.
- **Add** — the *Add a task…* bar at the top of each list; defaults follow the list (Today →
  due today, Important → high priority, a project → that project).
- **Edit** — click a task: the editor docks on the right (or opens as a sheet in a narrow
  window). Change title, notes, project, priority, due date; **⌘S** saves, **Esc** closes.
- **Quick edits** — right-click a task for priority, due date, project, done, or delete. Hover
  shows calendar / edit / delete buttons.
- **Calendar** — month grid with tasks per day; click a day to see and add its tasks; **drag a
  task onto another day** to reschedule.
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
| Widget shows *Failed to load widget… error 5* | Set the **Team** on both targets (step 4), clean (⇧⌘K) and rebuild |
| TaskWidget missing in **Edit Widgets** | Open the app from /Applications once, then log out and back in |
| Widget still uses an old server/port | Remove stray copies of `TaskWidget.app`, then `pkill -f TaskWidgetExtension` |
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
├── App/                    AppDelegate (hotkey, lifecycle), menu bar
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
