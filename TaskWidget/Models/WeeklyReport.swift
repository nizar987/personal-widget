import Foundation

/// Week boundaries that follow the user's locale (first weekday).
enum WeekRange {
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func interval(startingAt start: Date, calendar: Calendar = .current) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// Most recent `count` week starts, newest first.
    static func recent(_ count: Int, now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let current = start(of: now, calendar: calendar)
        return (0..<count).compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: current) }
    }

    /// "This Week", "Last Week", or "Sep 21 – 27".
    static func title(for start: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let current = self.start(of: now, calendar: calendar)
        if start == current { return "This Week" }
        if let last = calendar.date(byAdding: .weekOfYear, value: -1, to: current), start == last { return "Last Week" }
        return rangeText(for: start, calendar: calendar)
    }

    static func rangeText(for start: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "MMMd"
        return formatter.string(from: start, to: end)
    }
}

/// Everything the weekly report screen shows, computed from the task list.
struct WeeklyReport {
    struct DayCount: Identifiable {
        let day: Date
        let completed: Int
        let created: Int
        var id: Date { day }
    }

    struct Breakdown: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let interval: DateInterval
    /// Done during the week, newest first.
    let completed: [Task]
    let created: [Task]
    /// Due inside the week (any status).
    let dueThisWeek: [Task]
    /// Due inside the week and still open.
    let carriedOver: [Task]
    /// Open tasks due before the end of the week that are already past due.
    let overdue: [Task]
    let daily: [DayCount]
    let byProject: [Breakdown]
    let byPriority: [Breakdown]
    let previousCompletedCount: Int

    /// Share of tasks due this week that are done; nil when nothing was due.
    var completionRate: Double? {
        guard !dueThisWeek.isEmpty else { return nil }
        return Double(dueThisWeek.filter(\.completed).count) / Double(dueThisWeek.count)
    }

    var completedDelta: Int { completed.count - previousCompletedCount }

    init(tasks: [Task], weekStart: Date, now: Date = Date(), calendar: Calendar = .current) {
        let interval = WeekRange.interval(startingAt: weekStart, calendar: calendar)
        let contains = { (date: Date?) in date.map { interval.contains($0) && $0 < interval.end } ?? false }

        let done = tasks.filter { contains($0.completedDate) }
            .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
        let due = tasks.filter { contains($0.dueDay) }.sorted(by: TaskSort.byDateThenPriority)

        self.interval = interval
        completed = done
        created = tasks.filter { contains($0.createdDate) }
        dueThisWeek = due
        carriedOver = due.filter { !$0.completed }
        let today = calendar.startOfDay(for: now)
        overdue = tasks.filter { t in
            guard !t.completed, let due = t.dueDay else { return false }
            return due < today && due < interval.end
        }

        daily = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let finished = tasks.filter { $0.completedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }.count
            let made = tasks.filter { $0.createdDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }.count
            return DayCount(day: day, completed: finished, created: made)
        }

        byProject = Dictionary(grouping: done, by: \.project)
            .map { Breakdown(name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        byPriority = Priority.allCases.reversed().map { p in
            Breakdown(name: p.displayName, count: done.filter { $0.priority == p }.count)
        }

        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        let previous = WeekRange.interval(startingAt: previousStart, calendar: calendar)
        previousCompletedCount = tasks.filter { t in
            t.completedDate.map { previous.contains($0) && $0 < previous.end } ?? false
        }.count
    }

    /// Completed tasks grouped by local day, newest day first.
    func completedByDay(calendar: Calendar = .current) -> [(day: Date, tasks: [Task])] {
        let groups = Dictionary(grouping: completed) { calendar.startOfDay(for: $0.completedDate ?? interval.start) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
}
