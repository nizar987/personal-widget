import AppIntents
import SwiftUI
import Foundation

// MARK: - AddTask intent

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Creates a new task and syncs it to the desktop database.")

    @Parameter(title: "Title", description: "Task title")
    var title: String

    @Parameter(title: "Project", description: "Project/category name")
    var project: String

    @Parameter(title: "Priority", default: "medium")
    var priority: String

    @Parameter(title: "Due Date (YYYY-MM-DD)", default: "")
    var dueDate: String?

    init() { }

    init(title: String, project: String, priority: String, dueDate: String?) {
        self.title = title
        self.project = project
        self.priority = priority
        self.dueDate = dueDate
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title) to \(\.$project)")
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError(message: "Title cannot be empty")
        }
        guard !project.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError(message: "Project cannot be empty")
        }

        let url = Constants.apiBaseURL.appendingPathComponent("/api/tasks")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any?] = [
            "title": title,
            "project": project,
            "priority": priority.lowercased(),
            "due_date": (dueDate?.isEmpty == false) ? dueDate : nil,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject:
            payload.compactMapValues { $0 as Any })

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw InternalError(message: "HTTP \(http.statusCode): \(msg)")
        }

        return .result(view: AddTaskResultView(title: title, project: project))
    }

    struct ValidationError: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
    }

    struct InternalError: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
    }
}

struct AddTaskResultView: View {
    let title: String
    let project: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(project).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Toggle task intent

struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Task"
    static var description = IntentDescription("Toggles a task's completion status.")

    @Parameter(title: "Task ID")
    var taskId: Int

    init() { }

    init(taskId: Int) {
        self.taskId = taskId
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle task \(\.$taskId)")
    }

    func perform() async throws -> some IntentResult {
        var req = URLRequest(url: Constants.apiBaseURL.appendingPathComponent("/api/tasks/\(taskId)/toggle"))
        req.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InternalError(message: "Toggle failed")
        }
        return .result()
    }

    struct InternalError: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
    }
}

// MARK: - Shortcuts provider

struct Shortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: ["Add a task in \(.applicationName)", "Create task in \(.applicationName)"],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ToggleTaskIntent(),
            phrases: ["Toggle a task in \(.applicationName)"],
            shortTitle: "Toggle Task",
            systemImageName: "checkmark.circle"
        )
    }
}
