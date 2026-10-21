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
                due: Date?, scheduled: Date? = nil, description: String? = nil,
                status: TaskStatus? = nil) async -> Bool {
        let input = NewTaskInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            project: project.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            due_date: due.map(TaskDate.string(from:)),
            description: description,
            scheduled_date: scheduled.map(TaskDate.string(from:)),
            status: status
        )
        do {
            let created = try await api.createTask(input)
            withAnimation(springy) { tasks.insert(created, at: 0) }
            didMutate()
            warnIfServerDropped(doDate: input.scheduled_date != nil, status: status == .inProgress, in: created)
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
        flipped.status = flipped.completed ? .done : .backlog
        replaceLocally(flipped)
        do {
            replaceLocally(try await api.toggleTask(id: task.id))
            didMutate()
        } catch {
            replaceLocally(task)
            report(error)
        }
    }

    /// Moves a task along backlog → in progress → done (or back).
    func setStatus(_ task: Task, _ status: TaskStatus) async {
        guard task.stage != status else { return }
        await update(task, TaskPatch(status: status))
    }

    func update(_ task: Task, _ patch: TaskPatch) async {
        replaceLocally(Self.apply(patch, to: task))
        do {
            let saved = try await api.updateTask(id: task.id, patch)
            replaceLocally(saved)
            didMutate()
            var setsDoDate = false
            if case .set = patch.scheduledDate { setsDoDate = true }
            warnIfServerDropped(doDate: setsDoDate, status: patch.status == .inProgress, in: saved)
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

    /// A server built before the do date / status existed silently ignores those fields.
    private func warnIfServerDropped(doDate: Bool, status: Bool, in saved: Task) {
        let droppedDoDate = doDate && saved.scheduledDate == nil
        let droppedStatus = status && saved.status == nil
        guard droppedDoDate || droppedStatus else { return }
        errorMessage = "The TaskWidget server is out of date and didn't save the "
            + (droppedDoDate ? "do date" : "status")
            + ". Update it with backend/scripts/install-launch-agent.sh."
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
        if let v = patch.status {
            t.status = v
            t.completed = v == .done
            t.completedAt = v == .done ? (t.completedAt ?? TaskDate.timestampString(from: Date())) : nil
        } else if patch.completed == false, t.status == .done {
            t.status = .backlog
        } else if patch.completed == true {
            t.status = .done
        }
        switch patch.dueDate {
        case .set(let day): t.dueDate = day
        case .clear: t.dueDate = nil
        case nil: break
        }
        switch patch.scheduledDate {
        case .set(let day): t.scheduledDate = day
        case .clear: t.scheduledDate = nil
        case nil: break
        }
        return t
    }
}
