//! Request body validation. Error codes mirror the previous Next.js backend so clients keep working.

use chrono::NaiveDate;
use serde_json::{Map, Value};

use crate::model::{NewNote, NewTask, NoteChanges, Priority, TaskChanges};

pub const MAX_TITLE: usize = 200;
pub const MAX_DESCRIPTION: usize = 2000;
pub const MAX_PROJECT: usize = 60;
pub const MAX_NOTE_CONTENT: usize = 20000;

/// Machine-readable validation failure, serialized as `{"ok":false,"error":"<code>"}`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ValidationError(pub &'static str);

type Result<T> = std::result::Result<T, ValidationError>;

pub fn parse_new_task(body: &Value) -> Result<NewTask> {
    let obj = as_object(body)?;
    let title = required_text(obj, "title", MAX_TITLE, "title_required", "title_too_long")?;
    let project = required_text(
        obj,
        "project",
        MAX_PROJECT,
        "project_required",
        "project_too_long",
    )?;
    let description = optional_text(obj, "description", MAX_DESCRIPTION, "description_too_long")?
        .unwrap_or_default();
    let priority = obj
        .get("priority")
        .and_then(Value::as_str)
        .and_then(Priority::parse)
        .ok_or(ValidationError("invalid_priority"))?;
    let due_date = nullable_due_date(obj)?.flatten();
    let calendar_event_id = nullable_string(obj, "calendar_event_id").flatten();

    Ok(NewTask {
        title,
        description,
        project,
        priority,
        due_date,
        calendar_event_id,
    })
}

pub fn parse_changes(body: &Value) -> Result<TaskChanges> {
    let obj = as_object(body)?;
    let mut changes = TaskChanges::default();

    if obj.contains_key("title") {
        changes.title = Some(required_text(
            obj,
            "title",
            MAX_TITLE,
            "title_required",
            "title_too_long",
        )?);
    }
    changes.description =
        optional_text(obj, "description", MAX_DESCRIPTION, "description_too_long")?;
    if obj.contains_key("project") {
        changes.project = Some(required_text(
            obj,
            "project",
            MAX_PROJECT,
            "project_required",
            "project_too_long",
        )?);
    }
    if let Some(value) = obj.get("priority") {
        let parsed = value.as_str().and_then(Priority::parse);
        changes.priority = Some(parsed.ok_or(ValidationError("invalid_priority"))?);
    }
    changes.due_date = nullable_due_date(obj)?;
    changes.calendar_event_id = nullable_string(obj, "calendar_event_id");
    if let Some(value) = obj.get("completed") {
        changes.completed = Some(
            value
                .as_bool()
                .ok_or(ValidationError("invalid_completed"))?,
        );
    }
    Ok(changes)
}

/// Accepts strictly `YYYY-MM-DD` that is also a real calendar date.
pub fn is_valid_date(value: &str) -> bool {
    value.len() == 10 && NaiveDate::parse_from_str(value, "%Y-%m-%d").is_ok()
}

// MARK: - Helpers

fn as_object(body: &Value) -> Result<&Map<String, Value>> {
    body.as_object().ok_or(ValidationError("invalid_json"))
}

fn required_text(
    obj: &Map<String, Value>,
    key: &str,
    max: usize,
    missing: &'static str,
    too_long: &'static str,
) -> Result<String> {
    let text = obj
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or_default();
    if text.is_empty() {
        return Err(ValidationError(missing));
    }
    if text.chars().count() > max {
        return Err(ValidationError(too_long));
    }
    Ok(text.to_owned())
}

/// Missing key → `None`. Non-string values are treated as empty, like the old backend.
fn optional_text(
    obj: &Map<String, Value>,
    key: &str,
    max: usize,
    too_long: &'static str,
) -> Result<Option<String>> {
    let Some(value) = obj.get(key) else {
        return Ok(None);
    };
    let text = value.as_str().map(str::trim).unwrap_or_default();
    if text.chars().count() > max {
        return Err(ValidationError(too_long));
    }
    Ok(Some(text.to_owned()))
}

/// Missing key → `None`, explicit null/empty → `Some(None)`, otherwise `Some(Some(text))`.
fn nullable_string(obj: &Map<String, Value>, key: &str) -> Option<Option<String>> {
    let value = obj.get(key)?;
    let text = match value {
        Value::Null => return Some(None),
        Value::String(s) => s.trim().to_owned(),
        other => other.to_string(),
    };
    Some(if text.is_empty() { None } else { Some(text) })
}

fn nullable_due_date(obj: &Map<String, Value>) -> Result<Option<Option<String>>> {
    match nullable_string(obj, "due_date") {
        Some(Some(date)) if !is_valid_date(&date) => Err(ValidationError("invalid_due_date")),
        other => Ok(other),
    }
}

// MARK: - Notes

/// A note requires non-empty content.
pub fn parse_new_note(body: &Value) -> Result<NewNote> {
    let obj = as_object(body)?;
    let content = required_text(
        obj,
        "content",
        MAX_NOTE_CONTENT,
        "content_required",
        "content_too_long",
    )?;
    Ok(NewNote { content })
}

pub fn parse_note_changes(body: &Value) -> Result<NoteChanges> {
    let obj = as_object(body)?;
    let mut changes = NoteChanges::default();
    if obj.contains_key("content") {
        changes.content = Some(required_text(
            obj,
            "content",
            MAX_NOTE_CONTENT,
            "content_required",
            "content_too_long",
        )?);
    }
    Ok(changes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn new_task_requires_title_project_and_priority() {
        assert_eq!(
            parse_new_task(&json!({"project": "p", "priority": "low"}))
                .unwrap_err()
                .0,
            "title_required"
        );
        assert_eq!(
            parse_new_task(&json!({"title": "t", "priority": "low"}))
                .unwrap_err()
                .0,
            "project_required"
        );
        assert_eq!(
            parse_new_task(&json!({"title": "t", "project": "p"}))
                .unwrap_err()
                .0,
            "invalid_priority"
        );
        assert_eq!(
            parse_new_task(&json!([1, 2])).unwrap_err().0,
            "invalid_json"
        );
    }

    #[test]
    fn new_task_trims_and_accepts_null_due_date() {
        let task = parse_new_task(
            &json!({"title": "  Ship  ", "project": " wms ", "priority": "high", "due_date": null}),
        )
        .unwrap();
        assert_eq!(task.title, "Ship");
        assert_eq!(task.project, "wms");
        assert_eq!(task.due_date, None);
    }

    #[test]
    fn rejects_bad_dates_and_long_titles() {
        let bad_date =
            json!({"title": "t", "project": "p", "priority": "low", "due_date": "2026-02-30"});
        assert_eq!(parse_new_task(&bad_date).unwrap_err().0, "invalid_due_date");
        let long = json!({"title": "x".repeat(MAX_TITLE + 1), "project": "p", "priority": "low"});
        assert_eq!(parse_new_task(&long).unwrap_err().0, "title_too_long");
    }

    #[test]
    fn changes_distinguish_missing_and_null_due_date() {
        assert_eq!(parse_changes(&json!({})).unwrap().due_date, None);
        assert_eq!(
            parse_changes(&json!({"due_date": null})).unwrap().due_date,
            Some(None)
        );
        assert_eq!(
            parse_changes(&json!({"due_date": "2026-10-12"}))
                .unwrap()
                .due_date,
            Some(Some("2026-10-12".into()))
        );
    }

    #[test]
    fn changes_validate_completed_type() {
        assert_eq!(
            parse_changes(&json!({"completed": "yes"})).unwrap_err().0,
            "invalid_completed"
        );
        assert_eq!(
            parse_changes(&json!({"completed": true}))
                .unwrap()
                .completed,
            Some(true)
        );
    }
}
