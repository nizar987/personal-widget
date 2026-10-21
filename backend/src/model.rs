//! Domain types. JSON field names match the Swift client (`TaskWidget/Models/Task.swift`).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Priority {
    Low,
    Medium,
    High,
}

impl Priority {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "low" => Some(Self::Low),
            "medium" => Some(Self::Medium),
            "high" => Some(Self::High),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
        }
    }
}

/// Workflow stage: backlog → in progress → done. `done` is the same thing as `completed`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    #[default]
    Backlog,
    InProgress,
    Done,
}

impl Status {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "backlog" => Some(Self::Backlog),
            "in_progress" => Some(Self::InProgress),
            "done" => Some(Self::Done),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Backlog => "backlog",
            Self::InProgress => "in_progress",
            Self::Done => "done",
        }
    }

    pub fn is_done(self) -> bool {
        self == Self::Done
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub id: i64,
    pub title: String,
    #[serde(default)]
    pub description: String,
    pub project: String,
    pub priority: Priority,
    pub due_date: Option<String>,
    /// Day you plan to work on it (`YYYY-MM-DD`), separate from the deadline.
    #[serde(default)]
    pub scheduled_date: Option<String>,
    pub calendar_event_id: Option<String>,
    pub completed: bool,
    /// Always `done` when `completed` is true. Older servers don't send it.
    #[serde(default)]
    pub status: Status,
    pub created_at: String,
    pub updated_at: String,
    /// UTC `YYYY-MM-DD HH:MM:SS` when the task was last marked done; `None` while open.
    #[serde(default)]
    pub completed_at: Option<String>,
}

/// Validated input for creating a task.
#[derive(Debug, Clone)]
pub struct NewTask {
    pub title: String,
    pub description: String,
    pub project: String,
    pub priority: Priority,
    pub due_date: Option<String>,
    pub scheduled_date: Option<String>,
    pub calendar_event_id: Option<String>,
    pub status: Status,
}

/// Validated partial update. Outer `None` = leave unchanged; `Some(None)` = set NULL.
#[derive(Debug, Clone, Default)]
pub struct TaskChanges {
    pub title: Option<String>,
    pub description: Option<String>,
    pub project: Option<String>,
    pub priority: Option<Priority>,
    pub due_date: Option<Option<String>>,
    pub scheduled_date: Option<Option<String>>,
    pub calendar_event_id: Option<Option<String>>,
    pub completed: Option<bool>,
    /// Wins over `completed` when both are given.
    pub status: Option<Status>,
}

impl TaskChanges {
    pub fn is_empty(&self) -> bool {
        self.title.is_none()
            && self.description.is_none()
            && self.project.is_none()
            && self.priority.is_none()
            && self.due_date.is_none()
            && self.scheduled_date.is_none()
            && self.calendar_event_id.is_none()
            && self.completed.is_none()
            && self.status.is_none()
    }
}

/// Query filters for listing tasks. Dates are inclusive `YYYY-MM-DD` bounds.
#[derive(Debug, Clone, Default)]
pub struct TaskFilter {
    pub project: Option<String>,
    pub priority: Option<Priority>,
    pub completed: Option<bool>,
    pub status: Option<Status>,
    pub due_from: Option<String>,
    pub due_to: Option<String>,
    /// Date bounds also match `scheduled_date` (either date in range).
    pub include_scheduled: bool,
}

// MARK: - Notes

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Note {
    pub id: i64,
    pub content: String,
    pub created_at: String,
    pub updated_at: String,
}

/// Validated input for creating a note.
#[derive(Debug, Clone)]
pub struct NewNote {
    pub content: String,
}

/// Validated partial note update. Same convention as `TaskChanges`.
#[derive(Debug, Clone, Default)]
pub struct NoteChanges {
    pub content: Option<String>,
}

impl NoteChanges {
    pub fn is_empty(&self) -> bool {
        self.content.is_none()
    }
}
