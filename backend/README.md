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

# connect Claude Desktop / Claude Code over MCP (after install-launch-agent.sh)
./scripts/install-mcp.sh
```

| Variable          | Default                                              |
|-------------------|------------------------------------------------------|
| `TASKWIDGET_PORT` | `3220`                                               |
| `TASKWIDGET_DB`   | `~/Library/Application Support/TaskWidget/tasks.db`  |
| `RUST_LOG`        | `info`                                               |

Logs (LaunchAgent): `~/Library/Logs/TaskWidget/server.log`

### MCP (AI assistants)

`taskwidget-server mcp` speaks the [Model Context Protocol](https://modelcontextprotocol.io) on
stdin/stdout (logs on stderr), so an AI assistant can create and update tasks from a chat. It
opens the same database as the HTTP server (SQLite WAL, 5 s busy timeout) and posts the Darwin
notification `com.multiagent.taskwidget.tasksChanged` after every change, which makes the app
reload at once. Tools: `create_task`, `create_tasks`, `list_tasks`, `update_task`,
`list_projects` — they reuse the API validation and expose the do date as `do_date`.

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
| `GET`    | `/api/tasks`              | Filters: `project`, `priority`, `completed=true\|false`, `status=backlog\|in_progress\|done`, `from`, `to` (YYYY-MM-DD). `view=today\|week` (open tasks due *or* planned in that range), `view=projects` (names) |
| `POST`   | `/api/tasks`              | `title`, `project`, `priority` required; `description`, `due_date`, `scheduled_date` (do date), `status` (default `backlog`), `calendar_event_id` optional → `201` |
| `GET`    | `/api/tasks/:id`          | |
| `PATCH`  | `/api/tasks/:id`          | Any subset of fields; `"due_date": null` / `"scheduled_date": null` clears that date. `status` and `completed` stay in step: `status: "done"` ⇔ `completed: true`; `completed: false` moves a done task back to `backlog` |
| `DELETE` | `/api/tasks/:id`          | `{"ok": true, "message": "deleted"}` |
| `POST`   | `/api/tasks/:id/toggle`   | Flips `completed` (open → `done`, done → `backlog`) |
| `GET`    | `/api/notes`              | Plain notes, newest first. `search=<substring>` (literal, case-insensitive), `limit=<n>` (1–500) |
| `POST`   | `/api/notes`              | `content` required → `201` |
| `GET`    | `/api/notes/:id`          | |
| `PATCH`  | `/api/notes/:id`          | `content` |
| `DELETE` | `/api/notes/:id`          | |

Error codes: `invalid_json`, `invalid_id`, `title_required`, `title_too_long` (200),
`project_required`, `project_too_long` (60), `description_too_long` (2000), `invalid_priority`,
`invalid_due_date`, `invalid_scheduled_date`, `invalid_completed`, `invalid_status`, `task_not_found`, `not_found`, `internal_error`,
`content_required`, `content_too_long` (20000), `invalid_limit`, `note_not_found`.

## Develop

```bash
cargo test
cargo clippy --all-targets -- -D warnings
cargo fmt
```

```
src/
├── main.rs        CLI: serve | import | mcp
├── config.rs      env configuration
├── api.rs         routes, handlers, error envelope
├── validation.rs  request body parsing + error codes
├── repo.rs        SQLite repository (parameterized SQL)
├── import.rs      one-shot import over HTTP
├── mcp.rs         MCP server on stdio (tools for AI assistants)
├── notify.rs      Darwin notification telling the app to reload
└── model.rs       Task, Priority, Status, filters
tests/api_test.rs  end-to-end API tests (in-memory DB)
```
