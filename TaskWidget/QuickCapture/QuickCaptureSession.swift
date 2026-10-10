import Foundation
import Observation

/// State shared between the panel controller and its SwiftUI content: the typed text,
/// autocomplete suggestions and their keyboard selection.
@Observable
@MainActor
final class QuickCaptureSession {
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

    var suggestions: [QuickCaptureSuggestion] {
        guard dismissedText != text else { return [] }
        return QuickCaptureSuggester.suggestions(for: text, projects: projects, openCounts: openCounts, history: history)
    }

    func prepare(tasks: [Task], projects: [String]) {
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

    /// Returns true when the key was used for autocomplete (so the text field shouldn't see it).
    func handle(_ key: Key) -> Bool {
        let list = suggestions
        guard !list.isEmpty else { return false }
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
