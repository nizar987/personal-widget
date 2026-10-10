import Foundation

/// User-adjustable reminder settings, stored in UserDefaults.
struct DailyReminderSettings: Equatable {
    var isEnabled = true
    var hour = 8
    var minute = 0
    /// Minutes between repeats while "Understood" hasn't been pressed.
    var repeatInterval = 15
    /// Total notifications per day, including the first one.
    var repeatCount = 3

    private enum Key {
        static let enabled = "reminder.enabled"
        static let hour = "reminder.hour"
        static let minute = "reminder.minute"
        static let interval = "reminder.repeatInterval"
    }

    static let intervalChoices = [5, 10, 15, 30, 60]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        let base = DailyReminderSettings()
        defaults.register(defaults: [
            Key.enabled: base.isEnabled, Key.hour: base.hour,
            Key.minute: base.minute, Key.interval: base.repeatInterval,
        ])
    }

    static func load(_ defaults: UserDefaults = .standard) -> DailyReminderSettings {
        DailyReminderSettings(
            isEnabled: defaults.bool(forKey: Key.enabled),
            hour: min(max(defaults.integer(forKey: Key.hour), 0), 23),
            minute: min(max(defaults.integer(forKey: Key.minute), 0), 59),
            repeatInterval: max(defaults.integer(forKey: Key.interval), 1)
        )
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(hour, forKey: Key.hour)
        defaults.set(minute, forKey: Key.minute)
        defaults.set(repeatInterval, forKey: Key.interval)
    }
}

/// One notification to schedule.
struct DailyReminder: Equatable {
    /// `YYYY-MM-DD` of the day it's about.
    let dayKey: String
    /// 1-based position within that day's repeats.
    let attempt: Int
    let total: Int
    let fireDate: Date
    let title: String
    let subtitle: String?
    let body: String

    var identifier: String { "\(DailyReminderPlanner.identifierPrefix)\(dayKey).\(attempt)" }
}

/// Decides which reminder notifications should exist, given the tasks and settings.
enum DailyReminderPlanner {
    static let identifierPrefix = "taskwidget.daily."
    /// Scheduled ahead so reminders still fire if the app isn't running that morning.
    static let daysAhead = 7
    private static let maxListedTitles = 3

    static func plan(tasks: [Task], settings: DailyReminderSettings, acknowledgedDays: Set<String>,
                     now: Date = Date(), calendar: Calendar = .current) -> [DailyReminder] {
        guard settings.isEnabled, settings.repeatCount > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let open = tasks.filter { !$0.completed }

        return (0..<daysAhead).flatMap { offset -> [DailyReminder] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            let dayKey = TaskDate.string(from: day)
            guard !acknowledgedDays.contains(dayKey) else { return [] }

            let due = open.filter { $0.dueDay == day }.sorted(by: TaskSort.byPriority)
            let overdue = open.filter { ($0.dueDay ?? .distantFuture) < day }
            guard !due.isEmpty || !overdue.isEmpty else { return [] }

            guard let first = calendar.date(bySettingHour: settings.hour, minute: settings.minute,
                                             second: 0, of: day) else { return [] }
            let content = message(due: due, overdue: overdue)
            return (0..<settings.repeatCount).compactMap { index in
                guard let fire = calendar.date(byAdding: .minute, value: index * settings.repeatInterval, to: first),
                      fire > now else { return nil }
                return DailyReminder(
                    dayKey: dayKey, attempt: index + 1, total: settings.repeatCount, fireDate: fire,
                    title: content.title,
                    subtitle: index == 0 ? nil : "Reminder \(index + 1) of \(settings.repeatCount)",
                    body: content.body
                )
            }
        }
    }

    /// "🔴 Fix bug — wms · High". Dots match the priority colours used in the app and widget.
    static func line(for task: Task) -> String {
        let dot: String
        switch task.priority {
        case .high: dot = "🔴"
        case .medium: dot = "🟡"
        case .low: dot = "🔵"
        }
        let project = task.project.isEmpty ? "" : " — \(task.project)"
        return "\(dot) \(task.title)\(project) · \(task.priority.displayName)"
    }

    static func message(due: [Task], overdue: [Task]) -> (title: String, body: String) {
        let title: String
        switch (due.count, overdue.count) {
        case (0, let o): title = "\(o) overdue \(o == 1 ? "task" : "tasks") to finish"
        case (1, _): title = "1 task due today"
        case (let n, _): title = "\(n) tasks due today"
        }
        // List today's tasks; when nothing is due today, list the overdue ones instead.
        let listed = due.isEmpty ? overdue.sorted(by: TaskSort.byDateThenPriority) : due
        var lines = listed.prefix(maxListedTitles).map(line(for:))
        if listed.count > maxListedTitles { lines.append("+\(listed.count - maxListedTitles) more") }
        if !due.isEmpty && !overdue.isEmpty {
            lines.append("⚠︎ \(overdue.count) overdue")
        }
        return (title, lines.joined(separator: "\n"))
    }
}
