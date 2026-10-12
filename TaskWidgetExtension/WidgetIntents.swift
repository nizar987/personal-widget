import AppIntents
import WidgetKit

// Buttons inside the widget. WidgetKit reloads the timeline after each `perform`.

/// Switches the list a widget shows (tab bar, header tap, week-strip day).
struct SelectWidgetTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Widget List"
    static var isDiscoverable = false

    @Parameter(title: "Widget size") var scope: String
    @Parameter(title: "List") var tab: String

    init() {}

    init(scope: String, tab: WidgetTab) {
        self.scope = scope
        self.tab = tab.rawValue
    }

    func perform() async throws -> some IntentResult {
        WidgetUIState(tab: WidgetTab(rawValue: tab), page: 0).save(scope: scope)
        return .result()
    }
}

/// Moves between pages when a list has more tasks than fit.
struct ChangeWidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Change Widget Page"
    static var isDiscoverable = false

    @Parameter(title: "Widget size") var scope: String
    /// Page to show; the provider clamps it to the valid range.
    @Parameter(title: "Page") var page: Int

    init() {}

    init(scope: String, page: Int) {
        self.scope = scope
        self.page = page
    }

    func perform() async throws -> some IntentResult {
        var state = WidgetUIState.load(scope: scope)
        state.page = max(page, 0)
        state.save(scope: scope)
        return .result()
    }
}

/// Does nothing. Backs the widget's empty space so a stray click doesn't launch the app
/// (macOS opens the containing app for any click that isn't on a control).
struct WidgetNoOpIntent: AppIntent {
    static var title: LocalizedStringResource = "Widget Background"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Pushes a task's due date to tomorrow.
struct SnoozeTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Task to Tomorrow"
    static var isDiscoverable = false

    @Parameter(title: "Task ID") var taskId: Int

    init() {}

    init(taskId: Int) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        let tomorrow = TaskDate.string(from: TaskDate.day(offset: 1))
        _ = try await APIClient.shared.updateTask(id: taskId, TaskPatch(dueDate: .set(tomorrow)))
        return .result()
    }
}
