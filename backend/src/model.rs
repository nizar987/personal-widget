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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub id: i64,
    pub title: String,
    #[serde(default)]
    pub description: String,
    pub project: String,
    pub priority: Priority,
    pub due_date: Option<String>,
    pub calendar_event_id: Option<String>,
    pub completed: bool,
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
    pub calendar_event_id: Option<String>,
}

/// Validated partial update. Outer `None` = leave unchanged; `Some(None)` = set NULL.
#[derive(Debug, Clone, Default)]
pub struct TaskChanges {
    pub title: Option<String>,
    pub description: Option<String>,
    pub project: Option<String>,
    pub priority: Option<Priority>,
    pub due_date: Option<Option<String>>,
    pub calendar_event_id: Option<Option<String>>,
    pub completed: Option<bool>,
}

impl TaskChanges {
    pub fn is_empty(&self) -> bool {
        self.title.is_none()
            && self.description.is_none()
            && self.project.is_none()
            && self.priority.is_none()
            && self.due_date.is_none()
            && self.calendar_event_id.is_none()
            && self.completed.is_none()
    }
}

/// Query filters for listing tasks. Dates are inclusive `YYYY-MM-DD` bounds.
#[derive(Debug, Clone, Default)]
pub struct TaskFilter {
    pub project: Option<String>,
    pub priority: Option<Priority>,
    pub completed: Option<bool>,
    pub due_from: Option<String>,
    pub due_to: Option<String>,
}
