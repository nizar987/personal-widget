# TaskWidget — macOS Native App

Native macOS app to create and manage tasks, with calendar integration.

## Prerequisites

- **Xcode 15+** (Swift 5.9+)
- **macOS 13+** deployment target
- **Backend**: `multi-agent` running on `localhost:3210`

## Quick Start

1. **Open project in Xcode**:
   ```bash
   open /Users/muhammadnizaraulia/TaskWidget/TaskWidget.xcodeproj
   ```

2. **Build & Run**:
   - Product → Build (⌘B)
   - Product → Run (⌘R)

3. **App launches**:
   - Main window: Add task form + task list
   - Menu bar: Optional extra launcher

## API Contract

Backend: `localhost:3210/api/tasks`

### GET /api/tasks
Query params: `view=today|week|projects|all`

Response:
```json
{
  "ok": true,
  "data": [
    {
      "id": "uuid",
      "title": "Task title",
      "description": "optional",
      "project": "multi-agent",
      "priority": "high|medium|low",
      "due_date": "2026-10-15",
      "calendar_event_id": "optional-event-uuid",
      "completed": false
    }
  ]
}
```

### POST /api/tasks
```json
{
  "title": "...",
  "description": "...",
  "project": "...",
  "priority": "...",
  "due_date": "2026-10-15"
}
```

Response: `{"ok": true, "data": {"id": "...", ...}}`

### PATCH /api/tasks/[id]
Update any field, same schema as POST.

### DELETE /api/tasks/[id]
Response: `{"ok": true}`

### PATCH /api/tasks/[id]/toggle
Toggle `completed` flag.

Response: `{"ok": true, "data": {...}}`

## Architecture

```
TaskWidget (Swift/SwiftUI)
├── TaskWidget app (main window)
├── TaskWidgetExtension (Lock Screen widget)
├── Shared (constants, models)
└── Services
    ├── APIClient (HTTP via URLSession)
    └── CalendarService (EventKit)
```

## Development

- **Models**: `Shared/Constants.swift`, `TaskWidget/Models/Task.swift`
- **Networking**: `TaskWidget/Services/APIClient.swift`
- **Calendar**: `TaskWidgetExtension/CalendarService.swift`
- **UI**: `TaskWidget/ContentView.swift`

## Testing

No unit tests configured yet. Manual smoke test:

1. Open app
2. Add task (title + project + priority + date)
3. Task appears in list
4. Toggle checkbox
5. Delete task
6. Check menu bar widget updates

## Known Issues

- Base URL hardcoded to `localhost:3210` (OK for MVP)
- No offline support (design trade-off)
- Widget only syncs every 15 minutes (WidgetKit limitation)

## Deployment

Not configured for App Store submission yet. For distribution:

1. Create App ID in Apple Developer
2. Setup provisioning profile
3. Update `DEVELOPMENT_TEAM` in Xcode project
4. Archive & upload via Transporter

## Support

See `multi-agent` backend project for API details.
