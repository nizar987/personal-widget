import Foundation
import Observation

/// State shared between the panel controller and its SwiftUI content: the typed text,
/// autocomplete suggestions and their keyboard selection.
enum QuickCaptureMode: String, CaseIterable {
    case task, note

    var title: String { rawValue.capitalized }
    var icon: String { self == .task ? "checkmark.circle" : "note.text" }
    var shortcutLabel: String { self == .task ? "⌘T" : "⌘N" }
}

@Observable
@MainActor
final class QuickCaptureSession {
    /// Task or note. Notes skip the task parser — the text is saved as-is.
    var mode: QuickCaptureMode = .task
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            selectedIndex = 0
            navigated = false
            dismissedText = nil
        }
    }
    var errorMessage: String?
    private(set) var projects: [String] = []
    private(set) var history: [QuickCaptureHistoryItem] = []
    private(set) var openCounts: [String: Int] = [:]
    /// Bumped on every show so the view re-focuses the field.
    private(set) var presentation = 0
    /// Mode requested for the current presentation (e.g. ⌘N from Notes → note). Cleared
    /// as soon as the user interacts, so manual switching keeps working afterwards.
    var requestedMode: QuickCaptureMode?

    /// Highlighted suggestion row.
    var selectedIndex = 0
    /// True once ↑/↓ was used; then ↵ accepts the suggestion instead of saving.
    private(set) var navigated = false
    /// Esc hides suggestions until the text changes.
    private var dismissedText: String?

    private static let lastProjectKey = "quickCapture.lastProject"

    /// Project used when the text has no `#project`.
    var defaultProject: String {
        if let last = UserDefaults.standard.string(forKey: Self.lastProjectKey), !last.isEmpty { return last }
        return projects.first ?? "Inbox"
    }

    /// `//` at the start forces note mode without touching the picker.
    var effectiveMode: QuickCaptureMode {
        if text.hasPrefix("//") { return .note }
        return requestedMode ?? mode
    }

    /// Notes are saved as typed, so they never get autocomplete.
    var suggestions: [QuickCaptureSuggestion] {
        guard effectiveMode == .task, dismissedText != text else { return [] }
        return QuickCaptureSuggester.suggestions(for: text, projects: projects, openCounts: openCounts, history: history)
    }

    func prepare(tasks: [Task], projects: [String], mode: QuickCaptureMode? = nil) {
        requestedMode = mode
        text = ""
        errorMessage = nil
        update(tasks: tasks, projects: projects)
        presentation += 1
    }

    func update(tasks: [Task], projects: [String]) {
        self.projects = projects
        history = QuickCaptureSuggester.history(from: tasks)
        openCounts = QuickCaptureSuggester.openCounts(from: tasks)
    }

    func rememberProject(_ project: String) {
        UserDefaults.standard.set(project, forKey: Self.lastProjectKey)
    }

    func accept(_ suggestion: QuickCaptureSuggestion) {
        text = suggestion.completion
    }

    /// ⇥ (when no suggestion is showing): flip between task and note without the mouse.
    func toggleMode() {
        chooseMode(effectiveMode == .task ? .note : .task)
    }

    /// User picked a mode (picker click, ⇥, ⌘T / ⌘N) — their choice wins from now on.
    func chooseMode(_ newMode: QuickCaptureMode) {
        mode = newMode
        requestedMode = nil
        if newMode == .task, text.hasPrefix("//") {
            text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Keyboard

    enum Key {
        case tab, returnKey, escape, up, down

        init?(keyCode: UInt16) {
            switch keyCode {
            case 48: self = .tab
            case 36, 76: self = .returnKey
            case 53: self = .escape
            case 126: self = .up
            case 125: self = .down
            default: return nil
            }
        }
    }

    /// Returns true when the key was consumed (so the text field shouldn't see it): by
    /// autocomplete, or ⇥ switching task ↔ note when there's nothing to complete.
    func handle(_ key: Key) -> Bool {
        let list = suggestions
        guard !list.isEmpty else {
            guard key == .tab else { return false }
            toggleMode()
            return true
        }
        let index = min(selectedIndex, list.count - 1)
        switch key {
        case .tab:
            accept(list[index])
        case .returnKey:
            guard navigated else { return false }
            accept(list[index])
        case .escape:
            dismissedText = text
        case .down:
            selectedIndex = (index + 1) % list.count
            navigated = true
        case .up:
            selectedIndex = (index - 1 + list.count) % list.count
            navigated = true
        }
        return true
    }
}
