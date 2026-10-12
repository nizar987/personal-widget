//! End-to-end tests of the HTTP API against an in-memory database.

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use axum::Router;
use chrono::Local;
use http_body_util::BodyExt;
use serde_json::{json, Value};
use taskwidget_server::api::router_with_notes;
use taskwidget_server::repo::{NoteRepo, TaskRepo};
use tower::ServiceExt;

fn app() -> Router {
    router_with_notes(
        TaskRepo::in_memory().expect("in-memory db"),
        NoteRepo::in_memory().expect("in-memory db"),
    )
}

async fn call(app: &Router, method: Method, uri: &str, body: Option<Value>) -> (StatusCode, Value) {
    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header("content-type", "application/json")
        .body(body.map_or_else(Body::empty, |b| Body::from(b.to_string())))
        .expect("request");
    let response = app.clone().oneshot(request).await.expect("response");
    let status = response.status();
    let bytes = response
        .into_body()
        .collect()
        .await
        .expect("body")
        .to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn create(app: &Router, title: &str, due: Option<&str>) -> Value {
    let (status, body) = call(
        app,
        Method::POST,
        "/api/tasks",
        Some(json!({
            "title": title, "project": "wms", "priority": "medium", "due_date": due,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    body["data"].clone()
}

#[tokio::test]
async fn full_task_lifecycle() {
    let app = app();
    let task = create(&app, "Fix GD bug", Some("2026-10-12")).await;
    let id = task["id"].as_i64().unwrap();
    assert_eq!(task["completed"], json!(false));
    assert_eq!(task["description"], json!(""));

    let (status, body) = call(
        &app,
        Method::PATCH,
        &format!("/api/tasks/{id}"),
        Some(json!({"title": "Fix GD bug fast", "priority": "high", "due_date": null})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["data"]["title"], json!("Fix GD bug fast"));
    assert_eq!(body["data"]["priority"], json!("high"));
    assert_eq!(body["data"]["due_date"], Value::Null);

    let (_, body) = call(&app, Method::POST, &format!("/api/tasks/{id}/toggle"), None).await;
    assert_eq!(body["data"]["completed"], json!(true));
    assert!(body["data"]["completed_at"].is_string(), "{body}");

    let (status, body) = call(&app, Method::GET, &format!("/api/tasks/{id}"), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["ok"], json!(true));

    let (status, body) = call(&app, Method::DELETE, &format!("/api/tasks/{id}"), None).await;
    assert_eq!(
        (status, body),
        (StatusCode::OK, json!({"ok": true, "message": "deleted"}))
    );

    let (status, body) = call(&app, Method::GET, &format!("/api/tasks/{id}"), None).await;
    assert_eq!(
        (status, body),
        (
            StatusCode::NOT_FOUND,
            json!({"ok": false, "error": "task_not_found"})
        )
    );
}

#[tokio::test]
async fn list_filters_views_and_projects() {
    let app = app();
    let today = Local::now().date_naive().format("%Y-%m-%d").to_string();
    let done = create(&app, "done today", Some(&today)).await;
    create(&app, "open today", Some(&today)).await;
    create(&app, "someday", None).await;
    call(
        &app,
        Method::POST,
        &format!("/api/tasks/{}/toggle", done["id"]),
        None,
    )
    .await;

    let (_, all) = call(&app, Method::GET, "/api/tasks", None).await;
    assert_eq!(all["data"].as_array().unwrap().len(), 3);

    let (_, open) = call(&app, Method::GET, "/api/tasks?completed=false", None).await;
    assert_eq!(open["data"].as_array().unwrap().len(), 2);

    let (_, today_view) = call(&app, Method::GET, "/api/tasks?view=today", None).await;
    let titles: Vec<_> = today_view["data"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["title"].clone())
        .collect();
    assert_eq!(titles, [json!("open today")]);

    let (_, projects) = call(&app, Method::GET, "/api/tasks?view=projects", None).await;
    assert_eq!(projects["data"], json!(["wms"]));
}

#[tokio::test]
async fn rejects_invalid_input_with_error_codes() {
    let app = app();
    let cases = [
        (json!({"project": "p", "priority": "low"}), "title_required"),
        (json!({"title": "t", "priority": "low"}), "project_required"),
        (
            json!({"title": "t", "project": "p", "priority": "urgent"}),
            "invalid_priority",
        ),
        (
            json!({"title": "t", "project": "p", "priority": "low", "due_date": "10/12/2026"}),
            "invalid_due_date",
        ),
    ];
    for (payload, code) in cases {
        let (status, body) = call(&app, Method::POST, "/api/tasks", Some(payload)).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(body["error"], json!(code));
    }

    let (status, body) = call(&app, Method::PATCH, "/api/tasks/abc", Some(json!({}))).await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::BAD_REQUEST, json!("invalid_id"))
    );

    let (status, body) = call(&app, Method::POST, "/api/tasks/999/toggle", None).await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::NOT_FOUND, json!("task_not_found"))
    );

    let (status, body) = call(&app, Method::GET, "/api/tasks?from=yesterday", None).await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::BAD_REQUEST, json!("invalid_due_date"))
    );

    let (status, _) = call(&app, Method::GET, "/nope", None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn malformed_json_is_reported() {
    let app = app();
    let request = Request::builder()
        .method(Method::POST)
        .uri("/api/tasks")
        .header("content-type", "application/json")
        .body(Body::from("{not json"))
        .unwrap();
    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

// MARK: - Notes

async fn create_note(app: &Router, content: &str) -> Value {
    let (status, body) = call(
        app,
        Method::POST,
        "/api/notes",
        Some(json!({"content": content})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    body["data"].clone()
}

#[tokio::test]
async fn full_note_lifecycle() {
    let app = app();
    let note = create_note(&app, "Ide: tambah mode gelap").await;
    let id = note["id"].as_i64().unwrap();
    assert_eq!(note["content"], json!("Ide: tambah mode gelap"));
    assert!(note["created_at"].is_string());

    // Newest first.
    let second = create_note(&app, "Belanja: kopi, susu").await;
    let second_id = second["id"].as_i64().unwrap();
    let (_, body) = call(&app, Method::GET, "/api/notes", None).await;
    let notes = body["data"].as_array().unwrap();
    assert_eq!(notes.len(), 2);
    assert_eq!(notes[0]["id"], json!(second_id), "newest note first");

    // Search filters by substring.
    let (_, body) = call(&app, Method::GET, "/api/notes?search=kopi", None).await;
    let found = body["data"].as_array().unwrap();
    assert_eq!(found.len(), 1);
    assert_eq!(found[0]["id"], json!(second_id));

    // Search matches literally, not as a LIKE pattern.
    let (_, body) = call(&app, Method::GET, "/api/notes?search=%25", None).await;
    assert_eq!(body["data"].as_array().unwrap().len(), 0);

    // Limit caps the result size.
    let (_, body) = call(&app, Method::GET, "/api/notes?limit=1", None).await;
    assert_eq!(body["data"].as_array().unwrap().len(), 1);

    // Update content.
    let (status, body) = call(
        &app,
        Method::PATCH,
        &format!("/api/notes/{id}"),
        Some(json!({"content": "Ide: mode gelap + widget"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["data"]["content"], json!("Ide: mode gelap + widget"));

    // Get one.
    let (status, body) = call(&app, Method::GET, &format!("/api/notes/{id}"), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["ok"], json!(true));

    // Delete then 404.
    let (status, _) = call(&app, Method::DELETE, &format!("/api/notes/{id}"), None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = call(&app, Method::GET, &format!("/api/notes/{id}"), None).await;
    assert_eq!(
        (status, body),
        (
            StatusCode::NOT_FOUND,
            json!({"ok": false, "error": "note_not_found"})
        )
    );
}

#[tokio::test]
async fn note_validation_rejects_bad_input() {
    let app = app();
    let cases = [
        (json!({}), "content_required"),
        (json!({"content": "   "}), "content_required"),
        (json!({"content": 42}), "content_required"),
        (json!({"content": "x".repeat(20001)}), "content_too_long"),
    ];
    for (payload, code) in cases {
        let (status, body) = call(&app, Method::POST, "/api/notes", Some(payload)).await;
        assert_eq!(
            (status, &body),
            (
                StatusCode::BAD_REQUEST,
                &json!({"ok": false, "error": code})
            ),
            "payload should fail with {code}"
        );
    }

    // Empty update is rejected too.
    let note = create_note(&app, "ok").await;
    let id = note["id"].as_i64().unwrap();
    let (status, body) = call(
        &app,
        Method::PATCH,
        &format!("/api/notes/{id}"),
        Some(json!({"content": "  "})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"], json!("content_required"));

    // Invalid id / limit / unknown id.
    let (status, body) = call(&app, Method::GET, "/api/notes/abc", None).await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::BAD_REQUEST, json!("invalid_id"))
    );
    let (status, body) = call(&app, Method::GET, "/api/notes?limit=-3", None).await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::BAD_REQUEST, json!("invalid_limit"))
    );
    let (status, body) = call(&app, Method::GET, "/api/notes/9999", None).await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::NOT_FOUND, json!("note_not_found"))
    );
    let (status, body) = call(
        &app,
        Method::PATCH,
        "/api/notes/9999",
        Some(json!({"content": "x"})),
    )
    .await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::NOT_FOUND, json!("note_not_found"))
    );
    let (status, body) = call(&app, Method::DELETE, "/api/notes/9999", None).await;
    assert_eq!(
        (status, body["error"].clone()),
        (StatusCode::NOT_FOUND, json!("note_not_found"))
    );
}
