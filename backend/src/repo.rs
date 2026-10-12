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
        completed_at TEXT DEFAULT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
    CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project);
    CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed);
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
    completed, created_at, updated_at, completed_at";

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
        if let Some(from) = &filter.due_from {
            clauses.push("due_date >= ?");
            values.push(from.clone().into());
        }
        if let Some(to) = &filter.due_to {
            clauses.push("due_date <= ?");
            values.push(to.clone().into());
        }
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
            "INSERT INTO tasks (title, description, project, priority, due_date, calendar_event_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                task.title,
                task.description,
                task.project,
                task.priority.as_str(),
                task.due_date,
                task.calendar_event_id
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
                     calendar_event_id, completed, created_at, updated_at, completed_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
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
                    completed_at_for_import(t)
                ])?;
            }
        }
        tx.commit()?;
        Ok(inserted)
    }
}

/// Adds `completed_at` to databases created before it existed. Existing done tasks get their
/// `updated_at` as the best available completion time.
fn migrate(conn: &Connection) -> RepoResult<()> {
    let has_column = conn
        .prepare("SELECT 1 FROM pragma_table_info('tasks') WHERE name = 'completed_at'")?
        .exists([])?;
    if !has_column {
        conn.execute_batch(
            "ALTER TABLE tasks ADD COLUMN completed_at TEXT DEFAULT NULL;
             UPDATE tasks SET completed_at = updated_at WHERE completed = 1;",
        )?;
        tracing::info!("migrated tasks table: added completed_at");
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
    }
}
