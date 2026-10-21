//! Tells the TaskWidget app that tasks changed outside of it, so it reloads right away
//! instead of on its next background refresh.

/// Darwin notification name the app observes (`TaskStore`'s external-change listener).
pub const TASKS_CHANGED: &std::ffi::CStr = c"com.multiagent.taskwidget.tasksChanged";

#[cfg(target_os = "macos")]
pub fn tasks_changed() {
    extern "C" {
        fn notify_post(name: *const std::ffi::c_char) -> u32;
    }
    // SAFETY: `TASKS_CHANGED` is a valid, NUL-terminated, 'static C string; `notify_post`
    // only reads it for the duration of the call.
    let status = unsafe { notify_post(TASKS_CHANGED.as_ptr()) };
    if status != 0 {
        tracing::warn!(
            status,
            "notify_post failed; the app picks the change up on its next refresh"
        );
    }
}

#[cfg(not(target_os = "macos"))]
pub fn tasks_changed() {}
