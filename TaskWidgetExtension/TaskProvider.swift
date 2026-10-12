import WidgetKit
import SwiftUI

// MARK: - WidgetKit timeline

struct TaskProvider: TimelineProvider {
    typealias Entry = TaskEntry

    private static let refreshMinutes = 15
    private static let retryMinutes = 5

    func placeholder(in context: Context) -> TaskEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        _Concurrency.Task { completion(await Self.loadEntry(family: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        _Concurrency.Task {
            let entry = await Self.loadEntry(family: context.family)
            let minutes = entry.errorMessage == nil ? Self.refreshMinutes : Self.retryMinutes
            let next = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// All tasks (not just open ones) so today's completions stay visible and can be undone.
    private static func loadEntry(family: WidgetFamily) async -> TaskEntry {
        let now = Date()
        let state = WidgetUIState.load(scope: family.stateScope).normalized(now: now)
        do {
            let tasks = try await APIClient.shared.fetchTasks()
            return TaskEntry(date: now, tasks: tasks, errorMessage: nil, state: state)
        } catch {
            return TaskEntry(date: now, tasks: [], errorMessage: error.localizedDescription, state: state)
        }
    }
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [Task]
    let errorMessage: String?
    var state = WidgetUIState()

}

// MARK: - Sample data (placeholder, gallery, previews)

extension TaskEntry {
    static var sample: TaskEntry {
        func day(_ offset: Int) -> String { TaskDate.string(from: TaskDate.day(offset: offset)) }
        func task(_ id: Int, _ title: String, _ p: Priority, _ due: String?) -> Task {
            Task(id: id, title: title, description: "", project: "Personal", priority: p,
                 dueDate: due, calendarEventId: nil, completed: false, createdAt: "", updatedAt: "")
        }
        let tasks = [
            task(1, "Reply to important email", .high, day(0)),
            task(2, "Catch flight", .medium, day(0)),
            task(3, "Organize study notes", .low, day(-1)),
            task(4, "Plan next week", .high, day(2)),
            task(5, "Exercise", .high, nil),
            task(6, "Pick up package", .medium, day(1)),
            task(7, "Read 10 pages", .low, day(3)),
            task(8, "Plan a weekend outing", .low, nil),
            task(9, "Watch YouTube", .low, nil),
            {
                var done = task(10, "Morning standup", .medium, day(0))
                done.completed = true
                done.completedAt = TaskDate.timestampString(from: Date())
                return done
            }(),
        ]
        return TaskEntry(date: Date(), tasks: tasks, errorMessage: nil)
    }
}
