import SwiftUI

// MARK: - Date helpers

/// Converts between `Date` and the backend's `YYYY-MM-DD` strings.
enum TaskDate {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// Backend timestamps are SQLite `datetime('now')` values: UTC "YYYY-MM-DD HH:MM:SS".
    private static let utcTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func string(from date: Date) -> String { iso.string(from: date) }

    static func timestamp(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return utcTimestamp.date(from: String(string.prefix(19)))
    }

    static func timestampString(from date: Date) -> String { utcTimestamp.string(from: date) }

    static func date(from string: String) -> Date? { iso.date(from: String(string.prefix(10))) }

    /// Local midnight `days` from today.
    static func day(offset days: Int, from now: Date = Date()) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now
    }
}

extension Task {
    /// Due date at local midnight, or nil when absent/unparseable.
    var dueDay: Date? {
        guard let dueDate, !dueDate.isEmpty else { return nil }
        return TaskDate.date(from: dueDate)
    }

    func isDueByToday(_ now: Date = Date()) -> Bool {
        guard let d = dueDay else { return false }
        return d <= Calendar.current.startOfDay(for: now)
    }

    var createdDate: Date? { TaskDate.timestamp(from: createdAt) }
    var completedDate: Date? { completed ? TaskDate.timestamp(from: completedAt ?? updatedAt) : nil }

    func isOverdue(_ now: Date = Date()) -> Bool {
        guard let d = dueDay else { return false }
        return d < Calendar.current.startOfDay(for: now)
    }
}

extension Priority {
    var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}

// MARK: - Sorting & grouping

enum TaskSort {
    static func byPriority(_ a: Task, _ b: Task) -> Bool {
        a.priority.rank > b.priority.rank
    }

    /// Dated tasks first (soonest first), then by priority.
    static func byDateThenPriority(_ a: Task, _ b: Task) -> Bool {
        switch (a.dueDay, b.dueDay) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return byPriority(a, b)
        }
    }
}

/// Buckets open tasks into mutually exclusive LockDay-style sections.
struct TaskGroups {
    /// Overdue or due today.
    let today: [Task]
    /// High priority, not due yet.
    let important: [Task]
    /// Dated in the future, non-high priority.
    let upcoming: [Task]
    /// No due date, non-high priority.
    let someday: [Task]
    /// Everything with a date, soonest first (today included).
    let upNext: [Task]

    init(tasks: [Task], today now: Date) {
        let open = tasks.filter { !$0.completed }
        let dueToday = open.filter { $0.isDueByToday(now) }
        let rest = open.filter { !$0.isDueByToday(now) }

        today = dueToday.sorted(by: TaskSort.byDateThenPriority)
        important = rest.filter { $0.priority == .high }.sorted(by: TaskSort.byDateThenPriority)
        upcoming = rest.filter { $0.priority != .high && $0.dueDay != nil }.sorted(by: TaskSort.byDateThenPriority)
        someday = rest.filter { $0.priority != .high && $0.dueDay == nil }.sorted(by: TaskSort.byPriority)
        upNext = open.filter { $0.dueDay != nil }.sorted(by: TaskSort.byDateThenPriority)
    }
}

// MARK: - Relative due labels

enum DueLabel {
    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    /// "Overdue", "Today", "Tmrw", or "Oct 12"; nil when undated.
    static func text(for task: Task, now: Date) -> String? {
        guard let due = task.dueDay else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        if due < today { return "Overdue" }
        if due == today { return "Today" }
        if due == TaskDate.day(offset: 1, from: now) { return "Tmrw" }
        return short.string(from: due)
    }

    static func color(for task: Task, now: Date) -> Color {
        guard task.dueDay != nil else { return .secondary }
        return task.isOverdue(now) ? Palette.today : Palette.color(for: task.priority)
    }
}
