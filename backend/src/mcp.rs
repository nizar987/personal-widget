//! Model Context Protocol server over stdio, so an AI assistant (Claude Desktop, Claude Code,
//! Cursor, …) can create and update tasks straight from a chat.
//!
//! Speaks newline-delimited JSON-RPC 2.0 on stdin/stdout; logs must go to stderr. Writes go
//! directly to the SQLite file the HTTP server uses, then the app is told to reload.

use std::io::{self, BufRead, Write};

use chrono::{Days, Local, NaiveDate};
use serde_json::{json, Map, Value};

use crate::model::{NewTask, Status, Task, TaskFilter};
use crate::notify;
use crate::repo::TaskRepo;
use crate::validation::{self, ValidationError};

const SUPPORTED_VERSIONS: &[&str] = &["2025-06-18", "2025-03-26", "2024-11-05"];
const LATEST_VERSION: &str = "2025-06-18";
const DEFAULT_PROJECT: &str = "Inbox";
const MAX_BATCH: usize = 50;
const DEFAULT_LIMIT: usize = 50;
const MAX_LIMIT: usize = 200;

/// Reads requests until stdin closes.
pub fn serve_stdio(repo: &TaskRepo) -> io::Result<()> {
    let stdin = io::stdin().lock();
    let mut stdout = io::stdout().lock();
    for line in stdin.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        if let Some(response) = handle_message(repo, &line, Local::now().date_naive()) {
            writeln!(stdout, "{response}")?;
            stdout.flush()?;
        }
    }
    Ok(())
}

/// One incoming line → the response to write, or `None` for notifications.
pub fn handle_message(repo: &TaskRepo, raw: &str, today: NaiveDate) -> Option<Value> {
    let Ok(message) = serde_json::from_str::<Value>(raw) else {
        return Some(rpc_error(Value::Null, -32700, "parse error"));
    };
    match message {
        Value::Array(batch) => {
            let replies: Vec<Value> = batch
                .into_iter()
                .filter_map(|m| handle_request(repo, m, today))
                .collect();
            (!replies.is_empty()).then_some(Value::Array(replies))
        }
        single => handle_request(repo, single, today),
    }
}

fn handle_request(repo: &TaskRepo, message: Value, today: NaiveDate) -> Option<Value> {
    let method = message.get("method").and_then(Value::as_str)?.to_owned();
    // Requests carry an id; notifications (e.g. notifications/initialized) get no reply.
    let id = message.get("id").cloned()?;
    let params = message.get("params").cloned().unwrap_or(Value::Null);
    let result = match method.as_str() {
        "initialize" => initialize(&params, today),
        "ping" => json!({}),
        "tools/list" => json!({ "tools": tool_definitions(today) }),
        "tools/call" => call_tool(repo, &params, today),
        _ => return Some(rpc_error(id, -32601, "method not found")),
    };
    Some(json!({ "jsonrpc": "2.0", "id": id, "result": result }))
}

fn rpc_error(id: Value, code: i64, message: &str) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } })
}

fn initialize(params: &Value, today: NaiveDate) -> Value {
    let requested = params.get("protocolVersion").and_then(Value::as_str);
    let version = requested
        .filter(|v| SUPPORTED_VERSIONS.contains(v))
        .unwrap_or(LATEST_VERSION);
    json!({
        "protocolVersion": version,
        "capabilities": { "tools": {} },
        "serverInfo": { "name": "taskwidget", "version": env!("CARGO_PKG_VERSION") },
        "instructions": format!(
            "TaskWidget is the user's personal task list. {} When the user asks you to remember, \
             plan or track work, create tasks for it — split a plan into several tasks with \
             create_tasks. Use short, actionable titles. Reuse existing project names from \
             list_projects when one fits. Resolve relative dates (\"tomorrow\", \"besok\", \"next \
             Friday\") to YYYY-MM-DD yourself. do_date is the day the user plans to work on it; \
             due_date is the deadline. Status goes backlog → in_progress → done.",
            today_sentence(today)
        ),
    })
}

fn today_sentence(today: NaiveDate) -> String {
    format!(
        "Today is {} ({}).",
        today.format("%Y-%m-%d"),
        today.format("%A")
    )
}

// MARK: - Tool schemas

fn task_fields_schema() -> Map<String, Value> {
    let date = |what: &str| json!({ "type": "string", "format": "date", "description": what });
    let mut fields = Map::new();
    fields.insert(
        "title".into(),
        json!({ "type": "string", "description": "Short, actionable title (max 200 chars)." }),
    );
    fields.insert(
        "project".into(),
        json!({ "type": "string", "description": "Project name (max 60). Defaults to \"Inbox\"." }),
    );
    fields.insert(
        "priority".into(),
        json!({ "type": "string", "enum": ["low", "medium", "high"], "description": "Defaults to medium." }),
    );
    fields.insert(
        "description".into(),
        json!({ "type": "string", "description": "Notes / details (max 2000 chars)." }),
    );
    fields.insert(
        "do_date".into(),
        date("YYYY-MM-DD: the day the user plans to work on it."),
    );
    fields.insert("due_date".into(), date("YYYY-MM-DD: the deadline."));
    fields.insert(
        "status".into(),
        json!({ "type": "string", "enum": ["backlog", "in_progress", "done"], "description": "Defaults to backlog." }),
    );
    fields
}

fn tool_definitions(today: NaiveDate) -> Value {
    let fields = task_fields_schema();
    let new_task = json!({ "type": "object", "properties": fields, "required": ["title"] });
    let mut update_fields = fields.clone();
    for key in ["do_date", "due_date"] {
        update_fields.insert(
            key.into(),
            json!({ "type": ["string", "null"], "description": "YYYY-MM-DD, or null to clear." }),
        );
    }
    update_fields.insert(
        "id".into(),
        json!({ "type": "integer", "description": "Task id." }),
    );
    let today = today_sentence(today);
    json!([
        {
            "name": "create_task",
            "description": format!("Add one task to the user's TaskWidget list. {today}"),
            "inputSchema": new_task,
        },
        {
            "name": "create_tasks",
            "description": format!(
                "Add several tasks at once (1–{MAX_BATCH}), e.g. the steps of a plan. All are \
                 validated before any is saved. {today}"
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "tasks": { "type": "array", "items": new_task, "minItems": 1, "maxItems": MAX_BATCH }
                },
                "required": ["tasks"],
            },
        },
        {
            "name": "list_tasks",
            "description": format!(
                "List tasks. By default only open ones (backlog + in progress). {today}"
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "enum": ["open", "backlog", "in_progress", "done", "all"],
                        "description": "Defaults to open (backlog + in_progress).",
                    },
                    "project": { "type": "string" },
                    "view": {
                        "type": "string",
                        "enum": ["all", "today", "week"],
                        "description": "today / week: due or planned in that range.",
                    },
                    "limit": { "type": "integer", "minimum": 1, "maximum": MAX_LIMIT },
                },
            },
            "annotations": { "readOnlyHint": true },
        },
        {
            "name": "update_task",
            "description": "Change a task: move it through backlog → in_progress → done, \
                            reschedule, rename, re-prioritise. Only the given fields change.",
            "inputSchema": { "type": "object", "properties": update_fields, "required": ["id"] },
        },
        {
            "name": "list_projects",
            "description": "Project names already in use.",
            "inputSchema": { "type": "object", "properties": {} },
            "annotations": { "readOnlyHint": true },
        },
    ])
}

// MARK: - Tool calls

fn call_tool(repo: &TaskRepo, params: &Value, today: NaiveDate) -> Value {
    let name = params
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let empty = Value::Object(Map::new());
    let args = params.get("arguments").unwrap_or(&empty);
    let outcome = match name {
        "create_task" => create_task(repo, args),
        "create_tasks" => create_tasks(repo, args),
        "list_tasks" => list_tasks(repo, args, today),
        "update_task" => update_task(repo, args),
        "list_projects" => repo.projects().map(|p| json!(p)).map_err(|e| internal(&e)),
        other => Err(format!("unknown tool {other:?}")),
    };
    match outcome {
        Ok(data) => json!({
            "content": [{ "type": "text", "text": pretty(&data) }],
            "isError": false,
        }),
        Err(message) => json!({
            "content": [{ "type": "text", "text": message }],
            "isError": true,
        }),
    }
}

fn create_task(repo: &TaskRepo, args: &Value) -> Result<Value, String> {
    let input = parse_new(args)?;
    let task = repo.create(&input).map_err(|e| internal(&e))?;
    notify::tasks_changed();
    Ok(task_json(&task))
}

fn create_tasks(repo: &TaskRepo, args: &Value) -> Result<Value, String> {
    let items = args
        .get("tasks")
        .and_then(Value::as_array)
        .filter(|items| (1..=MAX_BATCH).contains(&items.len()))
        .ok_or_else(|| format!("tasks must be an array of 1–{MAX_BATCH} tasks"))?;
    let inputs = items
        .iter()
        .enumerate()
        .map(|(i, item)| parse_new(item).map_err(|e| format!("tasks[{i}]: {e}")))
        .collect::<Result<Vec<_>, _>>()?;
    let created = inputs
        .iter()
        .map(|input| repo.create(input).map(|t| task_json(&t)))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| internal(&e));
    notify::tasks_changed();
    Ok(json!({ "created": created? }))
}

fn list_tasks(repo: &TaskRepo, args: &Value, today: NaiveDate) -> Result<Value, String> {
    let (completed, status) = match args.get("status").and_then(Value::as_str) {
        None | Some("open") => (Some(false), None),
        Some("all") => (None, None),
        Some(s) => (
            None,
            Some(Status::parse(s).ok_or("status must be open, backlog, in_progress, done or all")?),
        ),
    };
    let range = match args.get("view").and_then(Value::as_str) {
        None | Some("all") => None,
        Some("today") => Some((today, today)),
        Some("week") => Some((today, today.checked_add_days(Days::new(7)).unwrap_or(today))),
        Some(_) => return Err("view must be all, today or week".into()),
    };
    let limit = match args.get("limit") {
        None | Some(Value::Null) => DEFAULT_LIMIT,
        Some(v) => v
            .as_u64()
            .filter(|n| *n >= 1)
            .map(|n| usize::try_from(n).unwrap_or(MAX_LIMIT).min(MAX_LIMIT))
            .ok_or("limit must be a positive integer")?,
    };
    let day = |d: NaiveDate| d.format("%Y-%m-%d").to_string();
    let filter = TaskFilter {
        project: args
            .get("project")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .map(str::to_owned),
        completed,
        status,
        due_from: range.map(|(from, _)| day(from)),
        due_to: range.map(|(_, to)| day(to)),
        include_scheduled: range.is_some(),
        ..TaskFilter::default()
    };
    let tasks = repo.list(&filter).map_err(|e| internal(&e))?;
    let total = tasks.len();
    let shown: Vec<Value> = tasks.iter().take(limit).map(task_json).collect();
    Ok(json!({ "today": day(today), "total": total, "tasks": shown }))
}

fn update_task(repo: &TaskRepo, args: &Value) -> Result<Value, String> {
    let id = args
        .get("id")
        .and_then(Value::as_i64)
        .filter(|id| *id > 0)
        .ok_or("id must be a positive integer")?;
    let changes = validation::parse_changes(&to_api_fields(args, false)?).map_err(explain)?;
    if changes.is_empty() {
        return Err("nothing to change: pass at least one field besides id".into());
    }
    let task = repo
        .update(id, &changes)
        .map_err(|e| internal(&e))?
        .ok_or_else(|| format!("no task with id {id}"))?;
    notify::tasks_changed();
    Ok(task_json(&task))
}

// MARK: - Mapping

fn parse_new(args: &Value) -> Result<NewTask, String> {
    validation::parse_new_task(&to_api_fields(args, true)?).map_err(explain)
}

/// Tool arguments → the HTTP API's field names, so the same validation applies.
/// New tasks get the default project and priority when the model leaves them out.
fn to_api_fields(args: &Value, with_defaults: bool) -> Result<Value, String> {
    let obj = args.as_object().ok_or("arguments must be an object")?;
    let mut out = Map::new();
    for (key, api_key) in [
        ("title", "title"),
        ("project", "project"),
        ("priority", "priority"),
        ("description", "description"),
        ("due_date", "due_date"),
        ("do_date", "scheduled_date"),
        ("status", "status"),
    ] {
        if let Some(value) = obj.get(key) {
            out.insert(api_key.into(), value.clone());
        }
    }
    if with_defaults {
        let blank = |v: Option<&Value>| {
            v.and_then(Value::as_str)
                .is_none_or(|s| s.trim().is_empty())
        };
        if blank(out.get("project")) {
            out.insert("project".into(), json!(DEFAULT_PROJECT));
        }
        if blank(out.get("priority")) {
            out.insert("priority".into(), json!("medium"));
        }
    }
    Ok(Value::Object(out))
}

/// Field names as the tools expose them (`do_date`, not `scheduled_date`).
fn task_json(task: &Task) -> Value {
    json!({
        "id": task.id,
        "title": task.title,
        "description": task.description,
        "project": task.project,
        "priority": task.priority.as_str(),
        "status": task.status.as_str(),
        "do_date": task.scheduled_date,
        "due_date": task.due_date,
        "created_at": task.created_at,
        "completed_at": task.completed_at,
    })
}

fn explain(err: ValidationError) -> String {
    let detail = match err.0 {
        "title_required" => "title is required",
        "title_too_long" => "title is longer than 200 characters",
        "project_required" => "project is required",
        "project_too_long" => "project is longer than 60 characters",
        "description_too_long" => "description is longer than 2000 characters",
        "invalid_priority" => "priority must be low, medium or high",
        "invalid_due_date" => "due_date must be a real date as YYYY-MM-DD",
        "invalid_scheduled_date" => "do_date must be a real date as YYYY-MM-DD",
        "invalid_status" => "status must be backlog, in_progress or done",
        "invalid_completed" => "completed must be true or false",
        "invalid_json" => "arguments must be an object",
        other => other,
    };
    format!("{detail} ({})", err.0)
}

fn internal(err: &dyn std::fmt::Display) -> String {
    tracing::error!(error = %err, "mcp tool failed");
    "internal error while saving to the task database".into()
}

fn pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 10, 21).unwrap()
    }

    fn send(repo: &TaskRepo, message: Value) -> Value {
        handle_message(repo, &message.to_string(), day()).expect("a reply")
    }

    fn call(repo: &TaskRepo, name: &str, arguments: Value) -> (bool, String) {
        let reply = send(
            repo,
            json!({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                   "params": {"name": name, "arguments": arguments}}),
        );
        let result = &reply["result"];
        (
            result["isError"].as_bool().unwrap(),
            result["content"][0]["text"].as_str().unwrap().to_owned(),
        )
    }

    #[test]
    fn initialize_negotiates_version_and_mentions_today() {
        let repo = TaskRepo::in_memory().unwrap();
        let reply = send(
            &repo,
            json!({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                   "params": {"protocolVersion": "2025-03-26", "capabilities": {}}}),
        );
        assert_eq!(reply["result"]["protocolVersion"], "2025-03-26");
        assert!(reply["result"]["instructions"]
            .as_str()
            .unwrap()
            .contains("2026-10-21 (Wednesday)"));
        let unknown = send(
            &repo,
            json!({"jsonrpc": "2.0", "id": 2, "method": "initialize",
                   "params": {"protocolVersion": "1999-01-01"}}),
        );
        assert_eq!(unknown["result"]["protocolVersion"], LATEST_VERSION);
    }

    #[test]
    fn notifications_get_no_reply_and_unknown_methods_error() {
        let repo = TaskRepo::in_memory().unwrap();
        let note = json!({"jsonrpc": "2.0", "method": "notifications/initialized"});
        assert!(handle_message(&repo, &note.to_string(), day()).is_none());
        let reply = send(&repo, json!({"jsonrpc": "2.0", "id": 3, "method": "nope"}));
        assert_eq!(reply["error"]["code"], -32601);
        let garbage = handle_message(&repo, "{not json", day()).unwrap();
        assert_eq!(garbage["error"]["code"], -32700);
    }

    #[test]
    fn lists_the_tools() {
        let repo = TaskRepo::in_memory().unwrap();
        let reply = send(
            &repo,
            json!({"jsonrpc": "2.0", "id": 4, "method": "tools/list"}),
        );
        let names: Vec<&str> = reply["result"]["tools"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["name"].as_str().unwrap())
            .collect();
        assert_eq!(
            names,
            [
                "create_task",
                "create_tasks",
                "list_tasks",
                "update_task",
                "list_projects"
            ]
        );
    }

    #[test]
    fn create_task_applies_defaults_and_keeps_both_dates() {
        let repo = TaskRepo::in_memory().unwrap();
        let (is_error, text) = call(
            &repo,
            "create_task",
            json!({"title": "Draft proposal", "do_date": "2026-10-22", "due_date": "2026-10-30"}),
        );
        assert!(!is_error, "{text}");
        let task: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(task["project"], DEFAULT_PROJECT);
        assert_eq!(task["priority"], "medium");
        assert_eq!(task["status"], "backlog");
        assert_eq!(task["do_date"], "2026-10-22");
        assert_eq!(task["due_date"], "2026-10-30");
    }

    #[test]
    fn create_tasks_is_all_or_nothing() {
        let repo = TaskRepo::in_memory().unwrap();
        let (is_error, text) = call(
            &repo,
            "create_tasks",
            json!({"tasks": [{"title": "ok"}, {"title": "bad", "due_date": "2026-02-30"}]}),
        );
        assert!(is_error);
        assert!(text.starts_with("tasks[1]: due_date"), "{text}");
        assert!(repo.list(&TaskFilter::default()).unwrap().is_empty());

        let (is_error, text) = call(
            &repo,
            "create_tasks",
            json!({"tasks": [{"title": "one", "project": "wms"}, {"title": "two", "priority": "high"}]}),
        );
        assert!(!is_error, "{text}");
        assert_eq!(repo.list(&TaskFilter::default()).unwrap().len(), 2);
    }

    #[test]
    fn update_moves_status_and_list_filters_open_tasks() {
        let repo = TaskRepo::in_memory().unwrap();
        let (_, text) = call(&repo, "create_task", json!({"title": "Ship"}));
        let id = serde_json::from_str::<Value>(&text).unwrap()["id"]
            .as_i64()
            .unwrap();

        let (is_error, text) = call(
            &repo,
            "update_task",
            json!({"id": id, "status": "in_progress", "do_date": null}),
        );
        assert!(!is_error, "{text}");
        assert!(text.contains("\"in_progress\""));

        let (_, text) = call(&repo, "list_tasks", json!({"status": "in_progress"}));
        assert_eq!(serde_json::from_str::<Value>(&text).unwrap()["total"], 1);

        call(&repo, "update_task", json!({"id": id, "status": "done"}));
        let (_, text) = call(&repo, "list_tasks", json!({}));
        assert_eq!(serde_json::from_str::<Value>(&text).unwrap()["total"], 0);

        let (is_error, text) = call(&repo, "update_task", json!({"id": id}));
        assert!(is_error && text.starts_with("nothing to change"));
        let (is_error, text) = call(&repo, "update_task", json!({"id": 999, "title": "x"}));
        assert!(is_error && text.contains("999"));
    }

    #[test]
    fn list_today_includes_planned_tasks() {
        let repo = TaskRepo::in_memory().unwrap();
        call(
            &repo,
            "create_task",
            json!({"title": "today", "do_date": "2026-10-21"}),
        );
        call(
            &repo,
            "create_task",
            json!({"title": "later", "do_date": "2026-11-21"}),
        );
        let (_, text) = call(&repo, "list_tasks", json!({"view": "today"}));
        let listed: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(listed["total"], 1);
        assert_eq!(listed["tasks"][0]["title"], "today");
    }
}
