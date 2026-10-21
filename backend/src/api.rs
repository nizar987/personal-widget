//! HTTP API. Every response uses the envelope `{"ok": bool, "data"?: .., "error"?: "<code>"}`.

use axum::extract::rejection::JsonRejection;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{Days, Local};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::model::{Priority, Status, TaskFilter};
use crate::repo::{NoteRepo, RepoError, RepoResult, TaskRepo};
use crate::validation::{self, ValidationError};

pub fn router(repo: TaskRepo) -> Router {
    router_with_notes(repo, NoteRepo::in_memory().expect("in-memory notes"))
}

/// Production entry point: both repos share the same SQLite file.
pub fn router_with_notes(repo: TaskRepo, notes: NoteRepo) -> Router {
    Router::new()
        .route("/api/health", get(health))
        .route("/api/tasks", get(list_tasks).post(create_task))
        .route(
            "/api/tasks/:id",
            get(get_task).patch(update_task).delete(delete_task),
        )
        .route("/api/tasks/:id/toggle", post(toggle_task))
        .route("/api/notes", get(list_notes).post(create_note))
        .route(
            "/api/notes/:id",
            get(get_note).patch(update_note).delete(delete_note),
        )
        .fallback(|| async { ApiError::NotFound("not_found") })
        .with_state(AppState { tasks: repo, notes })
}

/// Shared state: one repo per resource.
#[derive(Clone)]
pub struct AppState {
    pub tasks: TaskRepo,
    pub notes: NoteRepo,
}

// MARK: - Errors

#[derive(Debug)]
pub enum ApiError {
    BadRequest(&'static str),
    NotFound(&'static str),
    Internal,
}

impl From<ValidationError> for ApiError {
    fn from(err: ValidationError) -> Self {
        Self::BadRequest(err.0)
    }
}

impl From<RepoError> for ApiError {
    fn from(err: RepoError) -> Self {
        tracing::error!(error = %err, "repository failure");
        Self::Internal
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code) = match self {
            Self::BadRequest(code) => (StatusCode::BAD_REQUEST, code),
            Self::NotFound(code) => (StatusCode::NOT_FOUND, code),
            Self::Internal => (StatusCode::INTERNAL_SERVER_ERROR, "internal_error"),
        };
        (status, Json(json!({ "ok": false, "error": code }))).into_response()
    }
}

type ApiResult = Result<Response, ApiError>;

fn ok(data: impl serde::Serialize) -> Response {
    Json(json!({ "ok": true, "data": data })).into_response()
}

/// Runs blocking SQLite work off the async runtime.
async fn blocking<T, F>(repo: TaskRepo, work: F) -> Result<T, ApiError>
where
    T: Send + 'static,
    F: FnOnce(TaskRepo) -> RepoResult<T> + Send + 'static,
{
    tokio::task::spawn_blocking(move || work(repo))
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "blocking task panicked");
            ApiError::Internal
        })?
        .map_err(ApiError::from)
}

fn parse_id(raw: &str) -> Result<i64, ApiError> {
    raw.parse::<i64>()
        .ok()
        .filter(|id| *id > 0)
        .ok_or(ApiError::BadRequest("invalid_id"))
}

fn body(payload: Result<Json<Value>, JsonRejection>) -> Result<Value, ApiError> {
    payload
        .map(|Json(v)| v)
        .map_err(|_| ApiError::BadRequest("invalid_json"))
}

// MARK: - Handlers

async fn health() -> Response {
    ok(json!({ "service": "taskwidget-server", "version": env!("CARGO_PKG_VERSION") }))
}

#[derive(Debug, Deserialize)]
struct ListQuery {
    view: Option<String>,
    project: Option<String>,
    priority: Option<String>,
    completed: Option<String>,
    status: Option<String>,
    from: Option<String>,
    to: Option<String>,
}

async fn list_tasks(State(state): State<AppState>, Query(q): Query<ListQuery>) -> ApiResult {
    let repo = state.tasks;
    let today = Local::now().date_naive();
    let filter = match q.view.as_deref() {
        Some("projects") => return Ok(ok(blocking(repo, |r| r.projects()).await?)),
        Some("today") => open_between(today, today),
        Some("week") => open_between(today, today.checked_add_days(Days::new(7)).unwrap_or(today)),
        _ => filter_from(&q)?,
    };
    Ok(ok(blocking(repo, move |r| r.list(&filter)).await?))
}

fn open_between(from: chrono::NaiveDate, to: chrono::NaiveDate) -> TaskFilter {
    TaskFilter {
        completed: Some(false),
        due_from: Some(from.format("%Y-%m-%d").to_string()),
        due_to: Some(to.format("%Y-%m-%d").to_string()),
        // Views answer "what's on these days": due then, or planned for then.
        include_scheduled: true,
        ..TaskFilter::default()
    }
}

fn filter_from(q: &ListQuery) -> Result<TaskFilter, ApiError> {
    let priority = match q.priority.as_deref().filter(|p| !p.is_empty()) {
        Some(p) => Some(Priority::parse(p).ok_or(ApiError::BadRequest("invalid_priority"))?),
        None => None,
    };
    let status = match q.status.as_deref().filter(|s| !s.is_empty()) {
        Some(s) => Some(Status::parse(s).ok_or(ApiError::BadRequest("invalid_status"))?),
        None => None,
    };
    let date = |value: &Option<String>| -> Result<Option<String>, ApiError> {
        match value.as_deref().filter(|d| !d.is_empty()) {
            Some(d) if validation::is_valid_date(d) => Ok(Some(d.to_owned())),
            Some(_) => Err(ApiError::BadRequest("invalid_due_date")),
            None => Ok(None),
        }
    };
    Ok(TaskFilter {
        project: q.project.clone().filter(|p| !p.is_empty()),
        priority,
        completed: q.completed.as_deref().map(|c| c == "true"),
        status,
        due_from: date(&q.from)?,
        due_to: date(&q.to)?,
        include_scheduled: false,
    })
}

async fn create_task(
    State(state): State<AppState>,
    payload: Result<Json<Value>, JsonRejection>,
) -> ApiResult {
    let repo = state.tasks;
    let input = validation::parse_new_task(&body(payload)?)?;
    let task = blocking(repo, move |r| r.create(&input)).await?;
    Ok((StatusCode::CREATED, ok(task)).into_response())
}

async fn get_task(State(state): State<AppState>, Path(id): Path<String>) -> ApiResult {
    let repo = state.tasks;
    let id = parse_id(&id)?;
    let task = blocking(repo, move |r| r.get(id)).await?;
    task.map(ok).ok_or(ApiError::NotFound("task_not_found"))
}

async fn update_task(
    State(state): State<AppState>,
    Path(id): Path<String>,
    payload: Result<Json<Value>, JsonRejection>,
) -> ApiResult {
    let repo = state.tasks;
    let id = parse_id(&id)?;
    let changes = validation::parse_changes(&body(payload)?)?;
    let task = blocking(repo, move |r| r.update(id, &changes)).await?;
    task.map(ok).ok_or(ApiError::NotFound("task_not_found"))
}

async fn toggle_task(State(state): State<AppState>, Path(id): Path<String>) -> ApiResult {
    let repo = state.tasks;
    let id = parse_id(&id)?;
    let task = blocking(repo, move |r| r.toggle(id)).await?;
    task.map(ok).ok_or(ApiError::NotFound("task_not_found"))
}

async fn delete_task(State(state): State<AppState>, Path(id): Path<String>) -> ApiResult {
    let repo = state.tasks;
    let id = parse_id(&id)?;
    if blocking(repo, move |r| r.delete(id)).await? {
        Ok(Json(json!({ "ok": true, "message": "deleted" })).into_response())
    } else {
        Err(ApiError::NotFound("task_not_found"))
    }
}

// MARK: - Note handlers

#[derive(Debug, Deserialize)]
struct NoteListQuery {
    search: Option<String>,
    limit: Option<String>,
}

const MAX_NOTE_LIMIT: i64 = 500;

async fn list_notes(State(state): State<AppState>, Query(q): Query<NoteListQuery>) -> ApiResult {
    let limit = match q.limit.as_deref().map(str::trim).filter(|l| !l.is_empty()) {
        Some(raw) => Some(
            raw.parse::<i64>()
                .ok()
                .filter(|n| *n > 0)
                .ok_or(ApiError::BadRequest("invalid_limit"))?
                .min(MAX_NOTE_LIMIT),
        ),
        None => None,
    };
    let search = q
        .search
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned);
    let repo = state.notes;
    Ok(ok(blocking_notes(repo, move |r| {
        r.list(search.as_deref(), limit)
    })
    .await?))
}

async fn create_note(
    State(state): State<AppState>,
    payload: Result<Json<Value>, JsonRejection>,
) -> ApiResult {
    let input = validation::parse_new_note(&body(payload)?)?;
    let note = blocking_notes(state.notes, move |r| r.create(&input)).await?;
    Ok((StatusCode::CREATED, ok(note)).into_response())
}

async fn get_note(State(state): State<AppState>, Path(id): Path<String>) -> ApiResult {
    let id = parse_id(&id)?;
    let note = blocking_notes(state.notes, move |r| r.get(id)).await?;
    note.map(ok).ok_or(ApiError::NotFound("note_not_found"))
}

async fn update_note(
    State(state): State<AppState>,
    Path(id): Path<String>,
    payload: Result<Json<Value>, JsonRejection>,
) -> ApiResult {
    let id = parse_id(&id)?;
    let changes = validation::parse_note_changes(&body(payload)?)?;
    let note = blocking_notes(state.notes, move |r| r.update(id, &changes)).await?;
    note.map(ok).ok_or(ApiError::NotFound("note_not_found"))
}

async fn delete_note(State(state): State<AppState>, Path(id): Path<String>) -> ApiResult {
    let id = parse_id(&id)?;
    if blocking_notes(state.notes, move |r| r.delete(id)).await? {
        Ok(Json(json!({ "ok": true, "message": "deleted" })).into_response())
    } else {
        Err(ApiError::NotFound("note_not_found"))
    }
}

/// Same as `blocking` but for the notes repository.
async fn blocking_notes<T, F>(repo: NoteRepo, work: F) -> Result<T, ApiError>
where
    T: Send + 'static,
    F: FnOnce(NoteRepo) -> RepoResult<T> + Send + 'static,
{
    tokio::task::spawn_blocking(move || work(repo))
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "blocking task panicked");
            ApiError::Internal
        })?
        .map_err(ApiError::from)
}
