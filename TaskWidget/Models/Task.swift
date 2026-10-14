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

    enum CodingKeys: String, CodingKey {
        case id, title, description, project, priority
        case dueDate = "due_date"
        case calendarEventId = "calendar_event_id"
        case completed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case scheduledDate = "scheduled_date"
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
