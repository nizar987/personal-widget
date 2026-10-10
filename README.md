# TaskWidget

macOS native app for task management with calendar integration.

## Overview

- **Add tasks** with title, project, priority, and due date
- **Calendar sync** via EventKit
- **Lock Screen widget** showing today's task count
- **Menu bar launcher** (optional)
- **Siri integration** for quick-add via voice

## Getting Started

See [SETUP.md](SETUP.md) for installation and development guide.

## Features

### Main App Window
- Form to add new task
- List of tasks sorted by due date
- Checkbox to mark complete
- Delete with confirmation
- Filter by project and priority

### Lock Screen Widget
- Today's task count with emoji indicator
- Priority breakdown (high 🔴, medium 🟡, low 🟢)
- One-tap access to add task
- 15-minute refresh interval

### Calendar Integration
- Create calendar event from task
- Fetch events for today/week
- Link task ↔ event bidirectionally
- Auto-populate due date from event

## API

Backend: `localhost:3210/api/tasks`

Full API spec in [SETUP.md](SETUP.md#api-contract).

## Architecture

```
Swift/SwiftUI App
├── Models (Task, Priority)
├── Services
│   ├── APIClient (REST via URLSession)
│   └── CalendarService (EventKit)
└── Views
    ├── ContentView (main window)
    ├── TaskList
    ├── TaskForm
    └── Widget Extension
```

## Development Status

- [x] Core CRUD operations
- [x] Calendar integration
- [x] Widget extension
- [x] Siri AppIntent
- [ ] Unit tests
- [ ] Offline support
- [ ] App Store submission

## Requirements

- Xcode 15+
- Swift 5.9+
- macOS 13+
- Calendar permission (requested on first launch)

## License

Private project. See [multi-agent](../multi-agent) backend for details.
