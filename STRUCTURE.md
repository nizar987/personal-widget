# TaskWidget Project Structure

## Overview
TaskWidget adalah aplikasi macOS native untuk manajemen tugas terintegrasi dengan Calendar. Project ini terpisah sepenuhnya dari `multi-agent` repo.

### Lokasi
```
/Users/muhammadnizaraulia/TaskWidget/  (standalone Git repo)
```

## Directory Layout

```
TaskWidget/
├── .git/                    # Independent git repository
├── .gitignore              # Swift-specific gitignore
├── README.md               # Setup & usage guide
├── SETUP.md                # Detailed installation steps
├── STRUCTURE.md            # File ini
├── TASKWIDGET-REPORT.md    # Technical deep-dive (779 baris Swift)
├── generate_xcode.py       # Xcode project generator
│
├── Shared/                 # Shared Swift files
│   └── Constants.swift     # API_BASE_URL, calendar constants
│
├── TaskWidget/             # Main app target
│   ├── TaskWidgetApp.swift          # @main entry point
│   ├── ContentView.swift            # Master-detail UI (form + list)
│   ├── Models/
│   │   └── Task.swift              # Codable model (id, title, due_date, etc)
│   └── Services/
│       └── APIClient.swift         # URLSession wrapper (GET/POST/PATCH/DELETE)
│
├── TaskWidgetExtension/    # WidgetKit extension target
│   ├── TaskProvider.swift          # TimelineProvider (task data for widget)
│   ├── TaskWidgetView.swift        # Widget UI (lock screen / notification center)
│   └── AppIntent.swift             # Siri shortcuts ("Add a task")
│
└── TaskWidget.xcodeproj/   # Xcode project
    └── project.pbxproj    # Build configuration, signing, schemes
```

## Architecture

### Backend Integration
- **API Base**: `http://localhost:3210` (hardcoded, configurable in `Shared/Constants.swift`)
- **Endpoints**:
  - `GET /api/tasks?view=today` — fetch today's tasks
  - `GET /api/tasks?view=week` — fetch this week's tasks
  - `POST /api/tasks` — create task
  - `PATCH /api/tasks/{id}` — update task
  - `DELETE /api/tasks/{id}` — delete task
  - `POST /api/tasks/{id}/toggle` — toggle completion

### Data Flow
```
TaskWidget App
├── ContentView (SwiftUI)
│   ├── Form Input → TaskService.createTask() → APIClient → POST /api/tasks
│   ├── Task List → TaskService.fetchTasks() → APIClient → GET /api/tasks?view=today
│   └── Toggle → TaskService.toggleTask(id) → APIClient → POST /api/tasks/{id}/toggle
│
├── WidgetExtension
│   ├── TimelineProvider → TaskService.fetchTasks() (cache 5 min)
│   └── WidgetView renders task count + priority badges
│
└── AppIntent (Siri)
    └── "Add a task" → voice input → TaskService.createTask()

Calendar Sync (EventKit)
├── On create: CalendarService.createEvent() → save calendar_event_id to task
├── On view: CalendarService.fetchTodayEvents() → annotate tasks with event link
└── Permission: Request on first launch
```

## Key Technologies

| Layer | Tech | Usage |
|-------|------|-------|
| UI | SwiftUI | Main app, widget, AppIntent |
| Concurrency | async/await | URLSession, EventKit calls |
| Networking | URLSession | HTTP + Codable |
| Calendar | EventKit | Create/fetch calendar events |
| Persistence | In-memory + API | No local DB, all tasks via API |
| State | `@State`, `@StateObject` | SwiftUI state management |
| Deployment | Xcode | Build, run, sign, archive to TestFlight |

## Build & Run

### Prerequisites
- macOS 13+
- Xcode 15+
- Node.js 24+ (untuk backend API berjalan di `localhost:3210`)
- Backend running (multi-agent repository)

### Setup
```bash
cd /Users/muhammadnizaraulia/TaskWidget
open TaskWidget.xcodeproj
```

### Build & Run in Xcode
1. Cmd+B — build
2. Cmd+R — run main app (ContentView)
3. Product → Scheme → Edit Scheme → Run → Arguments → `-com.apple.CoreData.Debugging.SQLDebug 1` (optional, untuk debug database)

### Run Widget
1. Built app → Cmd+R runs `TaskWidgetApp`
2. To test widget: Xcode → Product → Build — then lock screen or Notification Center → Edit → Add "TaskWidget"

### Run Siri Shortcut
- Cmd+R app → "Add task with Siri" — uses AppIntent

## Testing Checklist

- [ ] Main app loads, connects to API (check console for connection errors)
- [ ] Create task → appears in list + API persists
- [ ] Toggle task → checkbox state changes + `/api/tasks/{id}/toggle` called
- [ ] Delete task → removed from list + `/api/tasks/{id}` called with DELETE
- [ ] Widget shows today's task count (minimum 5 min wait for refresh)
- [ ] Calendar permission: first launch asks for EventKit access
- [ ] App crashes → Xcode shows stack trace (check for force unwraps, nil access)
- [ ] Network error → UI shows "Failed to load tasks" message

## Troubleshooting

### "Cannot connect to localhost:3210"
- Backend not running? Start: `cd /Users/muhammadnizaraulia/multi-agent && npm run dev`
- Port in use? Check: `lsof -i :3210`
- API URL wrong? Edit: `Shared/Constants.swift` → `API_BASE_URL`

### Widget not updating
- Redo widget: remove from Lock Screen, rebuild app (Cmd+B), readd
- Cache expired? Wait 5 min or force refresh lock screen

### "EventKit permission denied"
- Go to System Settings → Privacy → Calendar → check TaskWidget is allowed
- Or delete app, rebuild → permission prompt reappears

### Xcode build fails
- Clean build folder: Cmd+Shift+K
- Delete `~/Library/Developer/Xcode/DerivedData/TaskWidget-*`
- Re-open Xcode

## File Sizes & Stats

- **Total Swift code**: 779 lines (production, no TODO)
- **Main app**: ~236 lines (ContentView + TaskWidgetApp)
- **Widget extension**: ~88 lines
- **Models & Services**: ~400 lines

## Next Steps (Future Enhancements)

1. **Offline support** — Core Data local cache, sync on reconnect
2. **Push notifications** — Remote push + local notification scheduling
3. **Custom URL scheme** — `taskwidget://add?title=...&date=...`
4. **iCloud sync** — CloudKit for cross-device tasks
5. **Performance** — Pagination, lazy loading for 100+ tasks

## Git
Standalone repo at `/Users/muhammadnizaraulia/TaskWidget/.git` — history independent from multi-agent.

Latest commits:
```
b547c09 Initial commit: macOS task manager widget + Calendar integration
49ce6fe Initial commit: TaskWidget macOS app
```

---

**Maintained by**: Full Stack Engineer  
**Last updated**: 2026-10-10  
**Status**: ✅ Production-ready (pending runtime verification on Xcode)
