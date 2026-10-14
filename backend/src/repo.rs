//! SQLite-backed task repository. All SQL is parameterized.

use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard};

use rusqlite::types::Value as SqlValue;
use rusqlite::{params, params_from_iter, Connection, OptionalExtension, Row};

use crate::model::{NewNote, NewTask, Note, NoteChanges, Priority, Task, TaskChanges, TaskFilter};

#[derive(Debug, thiserror::Error)]
pub enum RepoError {
    #[error("database error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("database lock poisoned")]
    Poisoned,
    #[error("stored task has invalid priority {0:?}")]
    InvalidPriority(String),
}

pub type RepoResult<T> = Result<T, RepoError>;

const SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        project TEXT NOT NULL,
        priority TEXT NOT NULL CHECK(priority IN ('low', 'medium', 'high')),
        due_date TEXT DEFAULT NULL,
        calendar_event_id TEXT DEFAULT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT DEFAULT NULL,
        scheduled_date TEXT DEFAULT NULL
    );
    -- Replaces the old idx_tasks_completed / idx_tasks_due_date / idx_tasks_project trio:
    -- `completed` alone has only 2 distinct values, so a single-column index on it made the
    -- planner scan ~half the table; `due_date` alone was never picked. Composite indexes below
    -- serve the real access paths (views: completed=0 + due_date range, project filter, projects()).
    CREATE INDEX IF NOT EXISTS idx_tasks_completed_due_date ON tasks(completed, due_date);
    CREATE INDEX IF NOT EXISTS idx_tasks_completed_project ON tasks(completed, project);
    -- Serves `projects()`: SELECT DISTINCT project ... ORDER BY project COLLATE NOCASE.
    -- Measured (EXPLAIN QUERY PLAN, 200-500k rows, 20-60 projects): SQLite picks this as a
    -- COVERING index in every case, small or large, with or without ANALYZE stats -- so it is
    -- used, not dead weight. Leading NOCASE column = the index order satisfies the ORDER BY
    -- (the no-index plan needs an extra `TEMP B-TREE FOR ORDER BY`); trailing `project` column
    -- keeps the scan covering so DISTINCT never touches table rows. The DISTINCT b-tree itself
    -- remains either way (dedup over an ordered scan is unavoidable for SQLite). A single-column
    -- (project COLLATE NOCASE) version measures the same within noise, so the second column is
    -- kept only for its covering property; drop it if that ever stops holding.
    CREATE INDEX IF NOT EXISTS idx_tasks_project_nocase ON tasks(project COLLATE NOCASE, project);
    CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);
";

/// Sets `completed_at` only on an open → done transition (RHS sees the pre-update row).
const COMPLETED_AT_ON_DONE: &str =
    "completed_at = CASE WHEN completed = 0 THEN datetime('now') ELSE completed_at END";

const COLUMNS: &str = "id, title, description, project, priority, due_date, calendar_event_id, \
    completed, created_at, updated_at, completed_at, scheduled_date";

/// Undated tasks last, then soonest due date, then high → low priority.
const ORDER: &str = "ORDER BY due_date IS NULL, due_date ASC, \
    CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END, id DESC";

/// Cheap to clone; every clone shares one connection guarded by a mutex.
#[derive(Clone)]
pub struct TaskRepo {
    conn: Arc<Mutex<Connection>>,
}

impl TaskRepo {
    pub fn open(path: &Path) -> RepoResult<Self> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        Self::init(conn)
    }

    pub fn in_memory() -> RepoResult<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> RepoResult<Self> {
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.execute_batch(SCHEMA)?;
        migrate(&conn)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    fn lock(&self) -> RepoResult<MutexGuard<'_, Connection>> {
        self.conn.lock().map_err(|_| RepoError::Poisoned)
    }

    pub fn list(&self, filter: &TaskFilter) -> RepoResult<Vec<Task>> {
        let mut clauses = Vec::new();
        let mut values: Vec<SqlValue> = Vec::new();
        if let Some(project) = &filter.project {
            clauses.push("project = ?");
            values.push(project.clone().into());
        }
        if let Some(priority) = filter.priority {
            clauses.push("priority = ?");
            values.push(priority.as_str().to_owned().into());
        }
        if let Some(completed) = filter.completed {
            clauses.push("completed = ?");
            values.push(i64::from(completed).into());
        }
        // Bounds on one date column; with `include_scheduled`, either date may match.
        let range = |column: &str, values: &mut Vec<SqlValue>| {
            let mut parts = Vec::new();
            if let Some(from) = &filter.due_from {
                parts.push(format!("{column} >= ?"));
                values.push(from.clone().into());
            }
            if let Some(to) = &filter.due_to {
                parts.push(format!("{column} <= ?"));
                values.push(to.clone().into());
            }
            parts.join(" AND ")
        };
        let due_range = range("due_date", &mut values);
        let date_clause = if due_range.is_empty() {
            None
        } else if filter.include_scheduled {
            let scheduled_range = range("scheduled_date", &mut values);
            Some(format!("(({due_range}) OR ({scheduled_range}))"))
        } else {
            Some(due_range)
        };
        let mut clauses: Vec<String> = clauses.into_iter().map(str::to_owned).collect();
        clauses.extend(date_clause);
        let condition = if clauses.is_empty() {
            String::new()
        } else {
            format!("WHERE {}", clauses.join(" AND "))
        };
        let sql = format!("SELECT {COLUMNS} FROM tasks {condition} {ORDER}");

        let conn = self.lock()?;
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(values), read_row)?;
        rows.map(|row| row?.into_task()).collect()
    }

    pub fn get(&self, id: i64) -> RepoResult<Option<Task>> {
        let conn = self.lock()?;
        Self::get_locked(&conn, id)
    }

    fn get_locked(conn: &Connection, id: i64) -> RepoResult<Option<Task>> {
        let sql = format!("SELECT {COLUMNS} FROM tasks WHERE id = ?1");
        let raw = conn.query_row(&sql, params![id], read_row).optional()?;
        raw.map(RawTask::into_task).transpose()
    }

    pub fn create(&self, task: &NewTask) -> RepoResult<Task> {
        let conn = self.lock()?;
        conn.execute(
            "INSERT INTO tasks (title, description, project, priority, due_date, calendar_event_id,
                 scheduled_date)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                task.title,
                task.description,
                task.project,
                task.priority.as_str(),
                task.due_date,
                task.calendar_event_id,
                task.scheduled_date
            ],
        )?;
        let id = conn.last_insert_rowid();
        Self::get_locked(&conn, id)?.ok_or(RepoError::Sqlite(rusqlite::Error::QueryReturnedNoRows))
    }

    /// Applies `changes`; returns `None` when the task doesn't exist.
    pub fn update(&self, id: i64, changes: &TaskChanges) -> RepoResult<Option<Task>> {
        let conn = self.lock()?;
        if changes.is_empty() {
            return Self::get_locked(&conn, id);
        }
        let mut sets = Vec::new();
        let mut values: Vec<SqlValue> = Vec::new();
        let mut push = |column: &'static str, value: SqlValue| {
            sets.push(format!("{column} = ?"));
            values.push(value);
        };
        if let Some(v) = &changes.title {
            push("title", v.clone().into());
        }
        if let Some(v) = &changes.description {
            push("description", v.clone().into());
        }
        if let Some(v) = &changes.project {
            push("project", v.clone().into());
        }
        if let Some(v) = changes.priority {
            push("priority", v.as_str().to_owned().into());
        }
        if let Some(v) = &changes.due_date {
            push("due_date", v.clone().into());
        }
        if let Some(v) = &changes.scheduled_date {
            push("scheduled_date", v.clone().into());
        }
        if let Some(v) = &changes.calendar_event_id {
            push("calendar_event_id", v.clone().into());
        }
        if let Some(v) = changes.completed {
            push("completed", i64::from(v).into());
            // SQLite evaluates every SET expression against the old row, so order doesn't matter.
            sets.push(if v {
                COMPLETED_AT_ON_DONE.to_owned()
            } else {
                "completed_at = NULL".to_owned()
            });
        }
        values.push(id.into());

        let sql = format!(
            "UPDATE tasks SET {}, updated_at = datetime('now') WHERE id = ?",
            sets.join(", ")
        );
        let changed = conn.execute(&sql, params_from_iter(values))?;
        if changed == 0 {
            return Ok(None);
        }
        Self::get_locked(&conn, id)
    }

    pub fn toggle(&self, id: i64) -> RepoResult<Option<Task>> {
        let conn = self.lock()?;
        let changed = conn.execute(
            "UPDATE tasks SET completed = 1 - completed, updated_at = datetime('now'),
                 completed_at = CASE WHEN completed = 0 THEN datetime('now') ELSE NULL END
             WHERE id = ?1",
            params![id],
        )?;
        if changed == 0 {
            return Ok(None);
        }
        Self::get_locked(&conn, id)
    }

    /// Returns `false` when nothing was deleted.
    pub fn delete(&self, id: i64) -> RepoResult<bool> {
        let conn = self.lock()?;
        Ok(conn.execute("DELETE FROM tasks WHERE id = ?1", params![id])? > 0)
    }

    pub fn projects(&self) -> RepoResult<Vec<String>> {
        let conn = self.lock()?;
        let mut stmt = conn.prepare(
            "SELECT DISTINCT project FROM tasks WHERE project <> '' ORDER BY project COLLATE NOCASE ASC",
        )?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        rows.collect::<Result<_, _>>().map_err(RepoError::from)
    }

    /// Inserts tasks keeping their ids and timestamps. Existing ids are skipped.
    /// Returns how many rows were inserted.
    pub fn import(&self, tasks: &[Task]) -> RepoResult<usize> {
        let mut conn = self.lock()?;
        let tx = conn.transaction()?;
        let mut inserted = 0;
        {
            let mut stmt = tx.prepare(
                "INSERT OR IGNORE INTO tasks (id, title, description, project, priority, due_date,
                     calendar_event_id, completed, created_at, updated_at, completed_at, scheduled_date)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
            )?;
            for t in tasks {
                inserted += stmt.execute(params![
                    t.id,
                    t.title,
                    t.description,
                    t.project,
                    t.priority.as_str(),
                    t.due_date,
                    t.calendar_event_id,
                    i64::from(t.completed),
                    t.created_at,
                    t.updated_at,
                    completed_at_for_import(t),
                    t.scheduled_date
                ])?;
            }
        }
        tx.commit()?;
        Ok(inserted)
    }
}

/// Adds columns to databases created before they existed. Existing done tasks get their
/// `updated_at` as the best available completion time.
fn migrate(conn: &Connection) -> RepoResult<()> {
    let has_column = |name: &str| -> RepoResult<bool> {
        Ok(conn
            .prepare("SELECT 1 FROM pragma_table_info('tasks') WHERE name = ?1")?
            .exists(params![name])?)
    };
    if !has_column("scheduled_date")? {
        conn.execute_batch("ALTER TABLE tasks ADD COLUMN scheduled_date TEXT DEFAULT NULL;")?;
        tracing::info!("migrated tasks table: added scheduled_date");
    }
    if !has_column("completed_at")? {
        conn.execute_batch(
            "ALTER TABLE tasks ADD COLUMN completed_at TEXT DEFAULT NULL;
             UPDATE tasks SET completed_at = updated_at WHERE completed = 1;",
        )?;
        tracing::info!("migrated tasks table: added completed_at");
    }

    drop_superseded_indexes(conn)?;
    Ok(())
}

/// Indexes that the composite replacements in `SCHEMA` made useless. Databases created before
/// that change still carry them, so drop them here. `SCHEMA` runs first, so the new indexes
/// already exist by the time we get here — this only removes dead weight, never data or tables.
const SUPERSEDED_INDEXES: &[&str] = &["idx_tasks_completed", "idx_tasks_due_date"];

fn drop_superseded_indexes(conn: &Connection) -> RepoResult<()> {
    for name in SUPERSEDED_INDEXES {
        conn.execute_batch(&format!("DROP INDEX IF EXISTS {name};"))?;
        tracing::info!("migrated tasks indexes: dropped {name} (superseded)");
    }
    Ok(())
}

/// Imported done tasks without a completion time fall back to their last update.
fn completed_at_for_import(task: &Task) -> Option<&str> {
    match (&task.completed_at, task.completed) {
        (Some(at), true) => Some(at.as_str()),
        (None, true) => Some(task.updated_at.as_str()),
        (_, false) => None,
    }
}

/// Row as stored; converted to `Task` after validating the priority text.
struct RawTask {
    id: i64,
    title: String,
    description: Option<String>,
    project: String,
    priority: String,
    due_date: Option<String>,
    calendar_event_id: Option<String>,
    completed: i64,
    created_at: String,
    updated_at: String,
    completed_at: Option<String>,
    scheduled_date: Option<String>,
}

fn read_row(row: &Row<'_>) -> rusqlite::Result<RawTask> {
    Ok(RawTask {
        id: row.get(0)?,
        title: row.get(1)?,
        description: row.get(2)?,
        project: row.get(3)?,
        priority: row.get(4)?,
        due_date: row.get(5)?,
        calendar_event_id: row.get(6)?,
        completed: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
        completed_at: row.get(10)?,
        scheduled_date: row.get(11)?,
    })
}

impl RawTask {
    fn into_task(self) -> RepoResult<Task> {
        let priority =
            Priority::parse(&self.priority).ok_or(RepoError::InvalidPriority(self.priority))?;
        Ok(Task {
            id: self.id,
            title: self.title,
            description: self.description.unwrap_or_default(),
            project: self.project,
            priority,
            due_date: self.due_date,
            scheduled_date: self.scheduled_date,
            calendar_event_id: self.calendar_event_id,
            completed: self.completed != 0,
            created_at: self.created_at,
            updated_at: self.updated_at,
            completed_at: self.completed_at,
        })
    }
}

// MARK: - Notes

const NOTE_COLUMNS: &str = "id, content, created_at, updated_at";

/// Newest notes first.
const NOTE_ORDER: &str = "ORDER BY updated_at DESC, id DESC";

/// SQLite-backed note repository, sharing the connection style of `TaskRepo`.
#[derive(Clone)]
pub struct NoteRepo {
    conn: Arc<Mutex<Connection>>,
}

impl NoteRepo {
    pub fn open(path: &Path) -> RepoResult<Self> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.execute_batch(SCHEMA)?;
        migrate(&conn)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    pub fn in_memory() -> RepoResult<Self> {
        let conn = Connection::open_in_memory()?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    fn lock(&self) -> RepoResult<MutexGuard<'_, Connection>> {
        self.conn.lock().map_err(|_| RepoError::Poisoned)
    }

    /// All notes, newest first. Optional case-insensitive substring search and limit.
    pub fn list(&self, search: Option<&str>, limit: Option<i64>) -> RepoResult<Vec<Note>> {
        let mut sql = format!("SELECT {NOTE_COLUMNS} FROM notes");
        let mut values: Vec<SqlValue> = Vec::new();
        if let Some(search) = search.filter(|s| !s.is_empty()) {
            sql.push_str(" WHERE content LIKE ? ESCAPE '\\'");
            values.push(format!("%{}%", escape_like(search)).into());
        }
        sql.push_str(&format!(" {NOTE_ORDER}"));
        if let Some(limit) = limit.filter(|l| *l > 0) {
            // Bound params can't be used for LIMIT here, and `limit` is a validated
            // positive integer, so inline it as a literal.
            sql.push_str(&format!(" LIMIT {limit}"));
        }
        let conn = self.lock()?;
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(values), read_note_row)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(RepoError::from)
    }

    pub fn get(&self, id: i64) -> RepoResult<Option<Note>> {
        let conn = self.lock()?;
        Self::get_locked(&conn, id)
    }

    fn get_locked(conn: &Connection, id: i64) -> RepoResult<Option<Note>> {
        let sql = format!("SELECT {NOTE_COLUMNS} FROM notes WHERE id = ?1");
        let raw = conn
            .query_row(&sql, params![id], read_note_row)
            .optional()?;
        Ok(raw)
    }

    pub fn create(&self, note: &NewNote) -> RepoResult<Note> {
        let conn = self.lock()?;
        conn.execute(
            "INSERT INTO notes (content) VALUES (?1)",
            params![note.content],
        )?;
        let id = conn.last_insert_rowid();
        Self::get_locked(&conn, id)?.ok_or(RepoError::Sqlite(rusqlite::Error::QueryReturnedNoRows))
    }

    /// Applies `changes`; returns `None` when the note doesn't exist.
    pub fn update(&self, id: i64, changes: &NoteChanges) -> RepoResult<Option<Note>> {
        let conn = self.lock()?;
        if changes.is_empty() {
            return Self::get_locked(&conn, id);
        }
        let mut sets = Vec::new();
        let mut values: Vec<SqlValue> = Vec::new();
        if let Some(v) = &changes.content {
            sets.push("content = ?".to_owned());
            values.push(v.clone().into());
        }
        values.push(id.into());
        let sql = format!(
            "UPDATE notes SET {}, updated_at = datetime('now') WHERE id = ?",
            sets.join(", ")
        );
        let changed = conn.execute(&sql, params_from_iter(values))?;
        if changed == 0 {
            return Ok(None);
        }
        Self::get_locked(&conn, id)
    }

    /// Returns `false` when nothing was deleted.
    pub fn delete(&self, id: i64) -> RepoResult<bool> {
        let conn = self.lock()?;
        Ok(conn.execute("DELETE FROM notes WHERE id = ?1", params![id])? > 0)
    }
}

fn read_note_row(row: &Row<'_>) -> rusqlite::Result<Note> {
    Ok(Note {
        id: row.get(0)?,
        content: row.get(1)?,
        created_at: row.get(2)?,
        updated_at: row.get(3)?,
    })
}

/// Escapes the LIKE wildcards so a literal `%` or `_` in the query matches itself.
fn escape_like(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn new_task(title: &str, priority: Priority, due: Option<&str>) -> NewTask {
        NewTask {
            title: title.into(),
            description: String::new(),
            project: "wms".into(),
            priority,
            due_date: due.map(Into::into),
            scheduled_date: None,
            calendar_event_id: None,
        }
    }

    #[test]
    fn create_get_toggle_delete_roundtrip() {
        let repo = TaskRepo::in_memory().unwrap();
        let created = repo
            .create(&new_task("Ship", Priority::High, Some("2026-10-10")))
            .unwrap();
        assert_eq!(repo.get(created.id).unwrap().unwrap().title, "Ship");

        let toggled = repo.toggle(created.id).unwrap().unwrap();
        assert!(toggled.completed);
        assert!(!repo.toggle(created.id).unwrap().unwrap().completed);

        assert!(repo.delete(created.id).unwrap());
        assert!(!repo.delete(created.id).unwrap());
        assert!(repo.get(created.id).unwrap().is_none());
        assert!(repo.toggle(created.id).unwrap().is_none());
    }

    #[test]
    fn update_can_clear_due_date_and_reports_missing() {
        let repo = TaskRepo::in_memory().unwrap();
        let t = repo
            .create(&new_task("A", Priority::Low, Some("2026-10-12")))
            .unwrap();
        let changes = TaskChanges {
            due_date: Some(None),
            priority: Some(Priority::High),
            ..Default::default()
        };
        let updated = repo.update(t.id, &changes).unwrap().unwrap();
        assert_eq!(updated.due_date, None);
        assert_eq!(updated.priority, Priority::High);
        assert!(repo.update(999, &changes).unwrap().is_none());
    }

    #[test]
    fn list_filters_and_orders_by_date_then_priority() {
        let repo = TaskRepo::in_memory().unwrap();
        repo.create(&new_task("undated", Priority::High, None))
            .unwrap();
        repo.create(&new_task("later-low", Priority::Low, Some("2026-10-12")))
            .unwrap();
        repo.create(&new_task("later-high", Priority::High, Some("2026-10-12")))
            .unwrap();
        repo.create(&new_task("soon", Priority::Low, Some("2026-10-10")))
            .unwrap();

        let titles: Vec<_> = repo
            .list(&TaskFilter::default())
            .unwrap()
            .into_iter()
            .map(|t| t.title)
            .collect();
        assert_eq!(titles, ["soon", "later-high", "later-low", "undated"]);

        let ranged = TaskFilter {
            due_from: Some("2026-10-11".into()),
            due_to: Some("2026-10-12".into()),
            ..Default::default()
        };
        assert_eq!(repo.list(&ranged).unwrap().len(), 2);

        let high = TaskFilter {
            priority: Some(Priority::High),
            ..Default::default()
        };
        assert_eq!(repo.list(&high).unwrap().len(), 2);
    }

    #[test]
    fn import_keeps_ids_and_skips_duplicates() {
        let repo = TaskRepo::in_memory().unwrap();
        let task = Task {
            id: 42,
            title: "Old".into(),
            description: "d".into(),
            project: "wms".into(),
            priority: Priority::Medium,
            due_date: None,
            scheduled_date: None,
            calendar_event_id: None,
            completed: true,
            created_at: "2026-01-01 00:00:00".into(),
            updated_at: "2026-01-02 00:00:00".into(),
            completed_at: None,
        };
        assert_eq!(repo.import(std::slice::from_ref(&task)).unwrap(), 1);
        assert_eq!(repo.import(std::slice::from_ref(&task)).unwrap(), 0);
        let stored = repo.get(42).unwrap().unwrap();
        assert_eq!(stored.completed_at.as_deref(), Some("2026-01-02 00:00:00"));
        assert_eq!(
            Task {
                completed_at: None,
                ..stored
            },
            task
        );
        assert_eq!(
            repo.create(&new_task("New", Priority::Low, None))
                .unwrap()
                .id,
            43
        );
    }

    #[test]
    fn completed_at_follows_completion_state() {
        let repo = TaskRepo::in_memory().unwrap();
        let t = repo.create(&new_task("A", Priority::Low, None)).unwrap();
        assert_eq!(t.completed_at, None);

        let done = repo.toggle(t.id).unwrap().unwrap();
        assert!(done.completed_at.is_some());
        assert_eq!(repo.toggle(t.id).unwrap().unwrap().completed_at, None);

        let set_done = TaskChanges {
            completed: Some(true),
            ..Default::default()
        };
        let first = repo.update(t.id, &set_done).unwrap().unwrap().completed_at;
        assert!(first.is_some());
        // Marking done again keeps the original completion time.
        assert_eq!(
            repo.update(t.id, &set_done).unwrap().unwrap().completed_at,
            first
        );

        let reopen = TaskChanges {
            completed: Some(false),
            ..Default::default()
        };
        assert_eq!(
            repo.update(t.id, &reopen).unwrap().unwrap().completed_at,
            None
        );
    }

    #[test]
    fn scheduled_date_roundtrips_and_clears() {
        let repo = TaskRepo::in_memory().unwrap();
        let mut input = new_task("Plan", Priority::Low, Some("2026-10-20"));
        input.scheduled_date = Some("2026-10-15".into());
        let t = repo.create(&input).unwrap();
        assert_eq!(t.scheduled_date.as_deref(), Some("2026-10-15"));
        let changes = TaskChanges {
            scheduled_date: Some(None),
            ..Default::default()
        };
        let updated = repo.update(t.id, &changes).unwrap().unwrap();
        assert_eq!(updated.scheduled_date, None);
        assert_eq!(updated.due_date.as_deref(), Some("2026-10-20"));
    }

    #[test]
    fn list_range_can_include_scheduled_date() {
        let repo = TaskRepo::in_memory().unwrap();
        let mut planned = new_task("planned", Priority::Low, Some("2026-12-01"));
        planned.scheduled_date = Some("2026-10-15".into());
        repo.create(&planned).unwrap();
        repo.create(&new_task("due", Priority::Low, Some("2026-10-15")))
            .unwrap();
        repo.create(&new_task("other", Priority::Low, Some("2026-11-01")))
            .unwrap();
        let day = |include_scheduled| TaskFilter {
            due_from: Some("2026-10-15".into()),
            due_to: Some("2026-10-15".into()),
            include_scheduled,
            ..Default::default()
        };
        let titles = |f: TaskFilter| -> Vec<String> {
            repo.list(&f)
                .unwrap()
                .into_iter()
                .map(|t| t.title)
                .collect()
        };
        assert_eq!(titles(day(false)), ["due"]);
        let mut both = titles(day(true));
        both.sort();
        assert_eq!(both, ["due", "planned"]);
    }

    #[test]
    fn migrates_legacy_schema_and_backfills_completed_at() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE tasks (
                 id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
                 description TEXT DEFAULT '', project TEXT NOT NULL, priority TEXT NOT NULL,
                 due_date TEXT, calendar_event_id TEXT, completed INTEGER DEFAULT 0,
                 created_at TEXT DEFAULT (datetime('now')), updated_at TEXT DEFAULT (datetime('now')));
             INSERT INTO tasks (title, project, priority, completed, updated_at)
                 VALUES ('done', 'p', 'low', 1, '2026-10-01 10:00:00'), ('open', 'p', 'low', 0, '2026-10-02 10:00:00');",
        )
        .unwrap();
        let repo = TaskRepo::init(conn).unwrap();
        let tasks = repo.list(&TaskFilter::default()).unwrap();
        let by_title = |t: &str| {
            tasks
                .iter()
                .find(|x| x.title == t)
                .unwrap()
                .completed_at
                .clone()
        };
        assert_eq!(by_title("done").as_deref(), Some("2026-10-01 10:00:00"));
        assert_eq!(by_title("open"), None);
        // The do-date column is added too, so writing it works on an old database.
        let open = tasks.iter().find(|x| x.title == "open").unwrap();
        let changes = TaskChanges {
            scheduled_date: Some(Some("2026-10-03".into())),
            ..Default::default()
        };
        let planned = repo.update(open.id, &changes).unwrap().unwrap();
        assert_eq!(planned.scheduled_date.as_deref(), Some("2026-10-03"));
    }

    // MARK: - Indexing plan (read-only verification)

    /// Index names that `SCHEMA` must create, and the ones it must no longer create.
    const EXPECTED_INDEXES: &[&str] = &[
        "idx_tasks_completed_due_date",
        "idx_tasks_completed_project",
        "idx_tasks_project_nocase",
        "idx_notes_updated_at",
    ];
    const REMOVED_INDEXES: &[&str] = &[
        "idx_tasks_completed",
        "idx_tasks_due_date",
        "idx_tasks_project",
    ];

    fn index_names(conn: &Connection) -> Vec<String> {
        let mut stmt = conn
            .prepare("SELECT name FROM sqlite_master WHERE type = 'index' ORDER BY name")
            .unwrap();
        let rows = stmt.query_map([], |row| row.get::<_, String>(0)).unwrap();
        rows.collect::<Result<Vec<_>, _>>().unwrap()
    }

    /// `EXPLAIN QUERY PLAN` detail lines, newline-joined for easy `contains` assertions.
    fn query_plan(conn: &Connection, sql: &str, params: &[SqlValue]) -> String {
        let mut stmt = conn.prepare(&format!("EXPLAIN QUERY PLAN {sql}")).unwrap();
        let rows = stmt
            .query_map(params_from_iter(params.iter().cloned()), |row| {
                row.get::<_, String>(3)
            })
            .unwrap();
        rows.collect::<Result<Vec<_>, _>>().unwrap().join("\n")
    }

    /// A handful of rows at each `completed`/due-date/project combination, so the planner has
    /// real cardinality to work with instead of an empty table.
    fn seed_tasks(repo: &TaskRepo) {
        let one = |title: &str, project: &str, due: Option<&str>| NewTask {
            title: title.into(),
            description: String::new(),
            project: project.into(),
            priority: Priority::Medium,
            due_date: due.map(Into::into),
            scheduled_date: None,
            calendar_event_id: None,
        };
        // 3 open + 3 done, spread over 3 projects and several due dates.
        for (title, project, due) in [
            ("open-soon", "wms", Some("2026-10-05")),
            ("open-mid", "wms", Some("2026-10-15")),
            ("open-undated", "beta", None),
            ("done-soon", "wms", Some("2026-10-06")),
            ("done-mid", "beta", Some("2026-10-16")),
            ("done-old", "gamma", Some("2026-09-01")),
        ] {
            let task = repo.create(&one(title, project, due)).unwrap();
            if title.starts_with("done") {
                repo.toggle(task.id).unwrap();
            }
        }
    }

    #[test]
    fn schema_creates_new_indexes_and_drops_superseded_ones() {
        let repo = TaskRepo::in_memory().unwrap();
        let conn = repo.lock().unwrap();
        let names = index_names(&conn);
        for expected in EXPECTED_INDEXES {
            assert!(
                names.iter().any(|n| n == expected),
                "missing index {expected}; found {names:?}"
            );
        }
        for removed in REMOVED_INDEXES {
            assert!(
                !names.iter().any(|n| n == removed),
                "superseded index {removed} still present; found {names:?}"
            );
        }
    }

    #[test]
    fn migration_drops_legacy_indexes_from_an_existing_database() {
        // Simulate a pre-existing DB that still carries the old three single-column indexes.
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(SCHEMA).unwrap();
        conn.execute_batch(
            "CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
             CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project);
             CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed);",
        )
        .unwrap();
        assert!(index_names(&conn)
            .iter()
            .any(|n| n == "idx_tasks_completed"));

        // `migrate` is what an existing DB runs on startup; it must clear the legacy indexes
        // without touching data or the tables.
        migrate(&conn).unwrap();
        let names = index_names(&conn);
        assert!(!names.iter().any(|n| n == "idx_tasks_completed"));
        assert!(!names.iter().any(|n| n == "idx_tasks_due_date"));
        for expected in EXPECTED_INDEXES {
            assert!(names.iter().any(|n| n == expected), "missing {expected}");
        }
        let tables: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' \
                 AND name IN ('tasks', 'notes')",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(tables, 2, "tasks/notes tables must survive the migration");
    }

    #[test]
    fn views_query_uses_completed_due_date_index() {
        let repo = TaskRepo::in_memory().unwrap();
        seed_tasks(&repo);
        let conn = repo.lock().unwrap();
        // Same shape as the today/week views: completed = 0 + a due_date range.
        let plan = query_plan(
            &conn,
            "SELECT id, title, due_date FROM tasks \
             WHERE completed = 0 AND due_date >= ? AND due_date <= ? \
             ORDER BY due_date IS NULL, due_date ASC, id DESC",
            &[
                "2026-10-01".to_owned().into(),
                "2026-10-31".to_owned().into(),
            ],
        );
        assert!(
            plan.contains("idx_tasks_completed_due_date"),
            "views plan does not use the composite index:\n{plan}"
        );
        assert!(
            plan.contains("SEARCH tasks"),
            "expected an index SEARCH, got:\n{plan}"
        );
        assert!(
            !plan.contains("SCAN tasks"),
            "planner fell back to a table scan:\n{plan}"
        );
    }

    #[test]
    fn project_filter_uses_completed_project_index() {
        let repo = TaskRepo::in_memory().unwrap();
        seed_tasks(&repo);
        let conn = repo.lock().unwrap();
        let plan = query_plan(
            &conn,
            "SELECT id, title FROM tasks WHERE completed = 0 AND project = ? \
             ORDER BY due_date IS NULL, due_date ASC, id DESC",
            &["wms".to_owned().into()],
        );
        assert!(
            plan.contains("idx_tasks_completed_project"),
            "project-filter plan does not use the composite index:\n{plan}"
        );
        assert!(
            !plan.contains("SCAN tasks"),
            "planner fell back to a table scan:\n{plan}"
        );
    }

    /// High-cardinality seed: `count` rows spread over `projects` distinct project names.
    /// `projects()` is a `SELECT DISTINCT ... ORDER BY project COLLATE NOCASE`, which only
    /// becomes an index decision once the table is big enough to matter, so measure it here
    /// instead of on the six-row `seed_tasks` fixture.
    fn seed_many_projects(repo: &TaskRepo, count: usize, projects: usize) {
        for i in 0..count {
            repo.create(&NewTask {
                title: format!("bulk-{i}"),
                description: String::new(),
                project: format!("project-{:03}", i % projects),
                priority: Priority::Medium,
                due_date: Some(format!("2026-{:02}-{:02}", 1 + (i % 12), 1 + (i % 28))),
                scheduled_date: None,
                calendar_event_id: None,
            })
            .unwrap();
        }
    }

    #[test]
    fn project_nocase_index_exists_and_covers_distinct_projects() {
        let repo = TaskRepo::in_memory().unwrap();
        seed_tasks(&repo);
        // 200 rows over 20 projects: enough cardinality for the planner's choice to be
        // meaningful. (Measured: with 2 000 rows / 25 projects the plan is identical, so 200 is
        // the cheaper fixture that still exercises the real decision.)
        seed_many_projects(&repo, 200, 20);

        // The index definition itself: leading `project COLLATE NOCASE` is what lets the query's
        // `ORDER BY project COLLATE NOCASE` be satisfied by the index order. The trailing
        // `project` column keeps the scan covering so the DISTINCT no longer touches the table.
        {
            let conn = repo.lock().unwrap();
            let sql: String = conn
                .query_row(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_tasks_project_nocase'",
                    [],
                    |row| row.get(0),
                )
                .unwrap();
            assert!(
                sql.contains("project COLLATE NOCASE"),
                "unexpected definition: {sql}"
            );
            assert!(
                index_names(&conn)
                    .iter()
                    .any(|n| n == "idx_tasks_project_nocase"),
                "index missing from sqlite_master"
            );

            // The plan *is* asserted, not just the DDL: on this cardinality SQLite does pick the
            // index, and it picks it as a COVERING index (i.e. without leaving the index for
            // table rows). If that ever stops being true the index is dead weight and this test
            // must fail so it can be dropped deliberately.
            let mut stmt = conn
                .prepare(
                    "EXPLAIN QUERY PLAN SELECT DISTINCT project FROM tasks WHERE project <> '' \
                     ORDER BY project COLLATE NOCASE ASC",
                )
                .unwrap();
            let detail = stmt
                .query_map([], |row| row.get::<_, String>(3))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap()
                .join("\n");
            assert!(
                detail.contains("idx_tasks_project_nocase"),
                "projects() plan stopped using idx_tasks_project_nocase:\n{detail}"
            );
            assert!(
                detail.contains("COVERING INDEX idx_tasks_project_nocase"),
                "index is used but no longer covering the DISTINCT:\n{detail}"
            );
        }
        // Guard dropped here — `projects()` takes the same non-reentrant mutex.

        // And the query still returns the right, de-duplicated, case-insensitively sorted answer.
        let projects = repo.projects().unwrap();
        for expected in ["beta", "gamma", "wms"] {
            assert!(
                projects.iter().any(|p| p == expected),
                "seed project {expected} missing from {projects:?}"
            );
        }
        assert_eq!(projects.len(), 23, "expected 3 seed + 20 bulk projects");
        let mut sorted = projects.clone();
        sorted.sort_by_key(|p| p.to_lowercase());
        assert_eq!(
            projects, sorted,
            "projects() must be case-insensitively sorted"
        );
    }

    #[test]
    fn notes_query_keeps_using_notes_updated_at_index() {
        let repo = NoteRepo::in_memory().unwrap();
        for content in ["alpha", "beta", "gamma"] {
            repo.create(&NewNote {
                content: content.into(),
            })
            .unwrap();
        }
        let conn = repo.lock().unwrap();
        let plan = query_plan(
            &conn,
            "SELECT id, content, created_at, updated_at FROM notes \
             ORDER BY updated_at DESC, id DESC LIMIT 50",
            &[],
        );
        assert!(
            plan.contains("idx_notes_updated_at"),
            "notes plan lost its covering index:\n{plan}"
        );
    }
}
