import WidgetKit
import SwiftUI

// MARK: - WidgetKit timeline

struct TaskProvider: TimelineProvider {
    typealias Entry = TaskEntry

    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), title: "—, Loading…", count: 0, priority: .medium)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        let entry = TaskEntry(date: Date(), title: "Widget kickoff", count: 2, priority: .high)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        Task {
            do {
                let tasks = try await APIClient.shared.fetchTasks(view: "today")
                let entry = TaskEntry(
                    date: Date(),
                    title: tasks.first?.title ?? "No tasks today",
                    count: tasks.count,
                    priority: tasks.first?.priority ?? .medium
                )
                let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                completion(Timeline(entries: [entry], policy: .after(next)))
            } catch {
                let entry = TaskEntry(date: Date(), title: "Error: \(error.localizedDescription)", count: 0, priority: .medium)
                let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
                completion(Timeline(entries: [entry], policy: .after(next)))
            }
        }
    }
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let title: String
    let count: Int
    let priority: Priority
}
