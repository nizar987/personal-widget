import Foundation

struct Task: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var description: String
    var project: String
    var priority: Priority
    var dueDate: String?       // YYYY-MM-DD
    var calendarEventId: String?
    var completed: Bool
    var createdAt: String
    var updatedAt: String
    /// UTC "YYYY-MM-DD HH:MM:SS" when marked done; nil while open.
    var completedAt: String? = nil
    /// YYYY-MM-DD: the day you plan to work on it (separate from the due date).
    var scheduledDate: String? = nil
    /// Workflow stage as the server sent it; nil from servers that predate it. Read `stage`.
    var status: TaskStatus? = nil

    /// Backlog → In Progress → Done. Always `.done` exactly when `completed` is true.
    var stage: TaskStatus {
        if completed { return .done }
        return status == .inProgress ? .inProgress : .backlog
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, project, priority
        case dueDate = "due_date"
        case calendarEventId = "calendar_event_id"
        case completed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case scheduledDate = "scheduled_date"
        case status
    }
}

/// Where a task is in its workflow. Reminders cover backlog and in-progress tasks.
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case backlog
    case inProgress = "in_progress"
    case done

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backlog: return "Backlog"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .backlog: return "tray"
        case .inProgress: return "play.circle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    /// The step after this one; done stays done.
    var next: TaskStatus {
        switch self {
        case .backlog: return .inProgress
        case .inProgress, .done: return .done
        }
    }
}

enum Priority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var color: String {
        switch self {
        case .low:    return "green"
        case .medium: return "orange"
        case .high:   return "red"
        }
    }

    var indicator: String {
        switch self {
        case .low:    return "●"
        case .medium: return "●"
        case .high:   return "●"
        }
    }
}

// MARK: - API Response Wrapper

struct TaskListResponse: Codable {
    let ok: Bool
    let data: [Task]
}

struct TaskResponse: Codable {
    let ok: Bool
    let data: Task
}

struct ProjectsResponse: Codable {
    let ok: Bool
    let data: [String]
}

struct ErrorResponse: Codable {
    let ok: Bool
    let error: String
}
