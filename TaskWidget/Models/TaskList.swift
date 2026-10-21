import SwiftUI

/// Built-in lists shown at the top of the sidebar.
enum SmartList: String, CaseIterable, Identifiable {
    case today, inProgress, upcoming, important, someday, all, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .inProgress: return "In Progress"
        case .upcoming: return "Upcoming"
        case .important: return "Important"
        case .someday: return "Someday"
        case .all: return "All Tasks"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .today: return "flame.fill"
        case .inProgress: return TaskStatus.inProgress.icon
        case .upcoming: return "bolt.fill"
        case .important: return "star.fill"
        case .someday: return "tray.fill"
        case .all: return "square.grid.2x2.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .today: return Palette.today
        case .inProgress: return Palette.color(for: .inProgress)
        case .upcoming: return Palette.upcoming
        case .important: return Palette.important
        case .someday: return .gray
        case .all: return Palette.project
        case .completed: return Palette.done
        }
    }
}

enum SidebarItem: Hashable {
    case smart(SmartList)
    case project(String)
    case calendar
    case notes
    /// Weekly report for the week starting at this local midnight.
    case report(weekStart: Date)

    var title: String {
        switch self {
        case .smart(let list): return list.title
        case .project(let name): return name
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .report(let start): return WeekRange.title(for: start)
        }
    }

    var icon: String {
        switch self {
        case .smart(let list): return list.icon
        case .project: return "folder.fill"
        case .calendar: return "calendar"
        case .notes: return "note.text"
        case .report: return "chart.bar.fill"
        }
    }

    var accent: Color {
        switch self {
        case .smart(let list): return list.accent
        case .project: return Palette.project
        case .calendar: return Palette.today
        case .notes: return Palette.upcoming
        case .report: return Palette.done
        }
    }

    /// Lists show task sections; calendar and reports have dedicated screens.
    var isTaskList: Bool {
        switch self {
        case .smart, .project: return true
        case .calendar, .notes, .report: return false
        }
    }
}

/// A titled group of tasks rendered as one card in the list.
struct TaskListSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let accent: Color
    let tasks: [Task]
}

/// Defaults the quick-add bar uses for the selected list.
struct QuickAddDefaults {
    let project: String?
    let priority: Priority
    let due: Date?
    /// Do date: Today / Upcoming plan the task for that day rather than setting a deadline.
    var scheduled: Date? = nil
    /// The In Progress list starts new tasks in progress; everywhere else they go to the backlog.
    var status: TaskStatus? = nil
}

extension SidebarItem {
    func quickAddDefaults(now: Date = Date()) -> QuickAddDefaults {
        switch self {
        case .smart(.today):
            return QuickAddDefaults(project: nil, priority: .medium, due: nil, scheduled: TaskDate.day(offset: 0, from: now))
        case .smart(.upcoming):
            return QuickAddDefaults(project: nil, priority: .medium, due: nil, scheduled: TaskDate.day(offset: 1, from: now))
        case .smart(.inProgress): return QuickAddDefaults(project: nil, priority: .medium, due: nil, status: .inProgress)
        case .smart(.important): return QuickAddDefaults(project: nil, priority: .high, due: nil)
        case .project(let name): return QuickAddDefaults(project: name, priority: .medium, due: nil)
        default: return QuickAddDefaults(project: nil, priority: .medium, due: nil)
        }
    }

    /// Tasks belonging to this list (before search), used for sidebar counts.
    func matching(_ tasks: [Task], now: Date) -> [Task] {
        switch self {
        case .smart(.today): return tasks.filter { !$0.completed && $0.isPlannedByToday(now) }
        case .smart(.inProgress): return tasks.filter { $0.stage == .inProgress }
        case .smart(.upcoming): return tasks.filter { !$0.completed && $0.planDay != nil && !$0.isPlannedByToday(now) }
        case .smart(.important): return tasks.filter { !$0.completed && $0.priority == .high }
        case .smart(.someday): return tasks.filter { !$0.completed && $0.planDay == nil }
        case .smart(.all): return tasks.filter { !$0.completed }
        case .smart(.completed): return tasks.filter(\.completed)
        case .project(let name): return tasks.filter { $0.project == name && !$0.completed }
        case .calendar, .notes, .report: return []
        }
    }

    func sections(from all: [Task], search: String, now: Date) -> [TaskListSection] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let source = query.isEmpty ? all : all.filter { $0.matches(query) }

        switch self {
        case .smart(.today):
            let items = matching(source, now: now)
            return Self.compact([
                section("overdue", "Overdue", "exclamationmark.circle.fill", Palette.today,
                        items.filter { $0.isOverdue(now) }.sorted(by: TaskSort.byDateThenPriority)),
                section("today", "Today", "flame.fill", Palette.upcoming,
                        items.filter { !$0.isOverdue(now) }.sorted(by: TaskSort.byPriority)),
            ])
        case .smart(.upcoming):
            return Self.byDay(matching(source, now: now), now: now)
        case .smart(.completed):
            return Self.compact([section("done", "Completed", "checkmark.circle.fill", Palette.done, matching(source, now: now))])
        case .smart(.inProgress), .smart(.important), .smart(.someday):
            let items = matching(source, now: now).sorted(by: TaskSort.byDateThenPriority)
            return Self.compact([section(title, title, icon, accent, items)])
        case .smart(.all):
            return Self.grouped(source, now: now)
        case .calendar, .notes, .report:
            return []
        case .project(let name):
            let mine = source.filter { $0.project == name }
            return Self.grouped(mine, now: now) + Self.compact([
                section("done", "Completed", "checkmark.circle.fill", Palette.done, mine.filter(\.completed)),
            ])
        }
    }

    // MARK: - Builders

    private func section(_ id: String, _ title: String, _ icon: String, _ accent: Color, _ tasks: [Task]) -> TaskListSection {
        TaskListSection(id: id, title: title, icon: icon, accent: accent, tasks: tasks)
    }

    private static func compact(_ sections: [TaskListSection]) -> [TaskListSection] {
        sections.filter { !$0.tasks.isEmpty }
    }

    private static func grouped(_ tasks: [Task], now: Date) -> [TaskListSection] {
        let g = TaskGroups(tasks: tasks, today: now)
        return compact([
            TaskListSection(id: "today", title: "Today", icon: "flame.fill", accent: Palette.today, tasks: g.today),
            TaskListSection(id: "important", title: "Important", icon: "star.fill", accent: Palette.important, tasks: g.important),
            TaskListSection(id: "upcoming", title: "Upcoming", icon: "bolt.fill", accent: Palette.upcoming, tasks: g.upcoming),
            TaskListSection(id: "someday", title: "Someday", icon: "tray.fill", accent: .gray, tasks: g.someday),
        ])
    }

    private static func byDay(_ tasks: [Task], now: Date) -> [TaskListSection] {
        let sorted = tasks.sorted(by: TaskSort.byDateThenPriority)
        let days = sorted.compactMap(\.planDay).reduce(into: [Date]()) { acc, d in
            if acc.last != d { acc.append(d) }
        }
        let title = DateFormatter()
        title.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return days.map { day in
            let label = day == TaskDate.day(offset: 1, from: now) ? "Tomorrow" : title.string(from: day)
            return TaskListSection(id: TaskDate.string(from: day), title: label, icon: "calendar",
                                   accent: Palette.upcoming, tasks: sorted.filter { $0.planDay == day })
        }
    }
}

extension Task {
    func matches(_ query: String) -> Bool {
        [title, description, project].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
