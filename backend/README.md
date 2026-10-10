# taskwidget-server

Local REST backend for the TaskWidget macOS app and desktop widget. Rust (axum + SQLite),
listening on **127.0.0.1:3220** only — it is never reachable from the network.

## Run

```bash
# one-off, from this folder
cargo run --release

# install as a LaunchAgent (starts at login, restarts on crash)
./scripts/install-launch-agent.sh

# remove the LaunchAgent (keeps your database)
./scripts/uninstall-launch-agent.sh
```

| Variable          | Default                                              |
|-------------------|------------------------------------------------------|
| `TASKWIDGET_PORT` | `3220`                                               |
| `TASKWIDGET_DB`   | `~/Library/Application Support/TaskWidget/tasks.db`  |
| `RUST_LOG`        | `info`                                               |

Logs (LaunchAgent): `~/Library/Logs/TaskWidget/server.log`

### Import from another server

Copies every task (ids, completion and timestamps preserved; existing ids skipped):

```bash
taskwidget-server import http://localhost:3210
```

## API

All responses use `{"ok": true, "data": …}` or `{"ok": false, "error": "<code>"}`.

| Method   | Path                      | Notes |
|----------|---------------------------|-------|
| `GET`    | `/api/health`             | Service name and version |
| `GET`    | `/api/tasks`              | Filters: `project`, `priority`, `completed=true\|false`, `from`, `to` (YYYY-MM-DD). `view=today\|week` (open tasks), `view=projects` (names) |
| `POST`   | `/api/tasks`              | `title`, `project`, `priority` required; `description`, `due_date`, `calendar_event_id` optional → `201` |
| `GET`    | `/api/tasks/:id`          | |
| `PATCH`  | `/api/tasks/:id`          | Any subset of fields; `"due_date": null` clears the date |
| `DELETE` | `/api/tasks/:id`          | `{"ok": true, "message": "deleted"}` |
| `POST`   | `/api/tasks/:id/toggle`   | Flips `completed` |

Error codes: `invalid_json`, `invalid_id`, `title_required`, `title_too_long` (200),
`project_required`, `project_too_long` (60), `description_too_long` (2000), `invalid_priority`,
`invalid_due_date`, `invalid_completed`, `task_not_found`, `not_found`, `internal_error`.

## Develop

```bash
cargo test
cargo clippy --all-targets -- -D warnings
cargo fmt
```

```
src/
├── main.rs        CLI: serve | import
├── config.rs      env configuration
├── api.rs         routes, handlers, error envelope
├── validation.rs  request body parsing + error codes
├── repo.rs        SQLite repository (parameterized SQL)
├── import.rs      one-shot import over HTTP
└── model.rs       Task, Priority, filters
tests/api_test.rs  end-to-end API tests (in-memory DB)
```
