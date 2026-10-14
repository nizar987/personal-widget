import SwiftUI
import Observation
import WidgetKit

/// Single source of truth for the app window. Mutations are optimistic and roll back on failure.
@Observable
@MainActor
final class TaskStore {
    private(set) var tasks: [Task] = [] {
        didSet { onTasksChanged?(tasks) }
    }
    /// Observers outside SwiftUI (e.g. reminder scheduling) hook in here.
    @ObservationIgnored var onTasksChanged: (([Task]) -> Void)?
    private(set) var isLoading = false
    private(set) var isOffline = false
    var errorMessage: String?

    private let api = APIClient.shared
    private let springy = Animation.spring(response: 0.38, dampingFraction: 0.82)

    var projects: [String] {
        Array(Set(tasks.map(\.project).filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func task(id: Int?) -> Task? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await api.fetchTasks()
            withAnimation(springy) { tasks = fresh }
            isOffline = false
            errorMessage = nil
        } catch {
            isOffline = true
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mutations

    @discardableResult
    func create(title: String, project: String, priority: Priority,
                due: Date?, scheduled: Date? = nil, description: String? = nil) async -> Bool {
        let input = NewTaskInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            project: project.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            due_date: due.map(TaskDate.string(from:)),
            description: description,
            scheduled_date: scheduled.map(TaskDate.string(from:))
        )
        do {
            let created = try await api.createTask(input)
            withAnimation(springy) { tasks.insert(created, at: 0) }
            didMutate()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func toggle(_ task: Task) async {
        var flipped = task
        flipped.completed.toggle()
        flipped.completedAt = flipped.completed ? TaskDate.timestampString(from: Date()) : nil
        replaceLocally(flipped)
        do {
            replaceLocally(try await api.toggleTask(id: task.id))
            didMutate()
        } catch {
            replaceLocally(task)
            report(error)
        }
    }

    func update(_ task: Task, _ patch: TaskPatch) async {
        replaceLocally(Self.apply(patch, to: task))
        do {
            replaceLocally(try await api.updateTask(id: task.id, patch))
            didMutate()
        } catch {
            replaceLocally(task)
            report(error)
        }
    }

    func delete(_ task: Task) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        _ = withAnimation(springy) { tasks.remove(at: index) }
        do {
            try await api.deleteTask(id: task.id)
            didMutate()
        } catch {
            withAnimation(springy) { tasks.insert(task, at: min(index, tasks.count)) }
            report(error)
        }
    }

    func deleteCompleted() async {
        for task in tasks where task.completed {
            await delete(task)
        }
    }

    // MARK: - Helpers

    private func replaceLocally(_ task: Task) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation(springy) {
            var copy = tasks
            copy[i] = task
            tasks = copy
        }
    }

    private func didMutate() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        if case APIError.network = error { isOffline = true }
    }

    private static func apply(_ patch: TaskPatch, to task: Task) -> Task {
        var t = task
        if let v = patch.title { t.title = v }
        if let v = patch.description { t.description = v }
        if let v = patch.project { t.project = v }
        if let v = patch.priority { t.priority = v }
        if let v = patch.completed {
            t.completed = v
            t.completedAt = v ? (t.completedAt ?? TaskDate.timestampString(from: Date())) : nil
        }
        switch patch.dueDate {
        case .set(let day): t.dueDate = day
        case .clear: t.dueDate = nil
        case nil: break
        }
        return t
    }
}
