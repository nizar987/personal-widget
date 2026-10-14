import Foundation

/// User-adjustable reminder settings, stored in UserDefaults.
struct DailyReminderSettings: Equatable {
    var isEnabled = true
    /// Daily summary time; repeats for due tasks start after it.
    var hour = 8
    var minute = 0
    /// Last moment of the day a repeat may fire.
    var endHour = 21
    var endMinute = 0
    /// Minutes between repeats while a due / overdue task is still open.
    var repeatInterval = 60

    private enum Key {
        static let enabled = "reminder.enabled"
        static let hour = "reminder.hour"
        static let minute = "reminder.minute"
        static let endHour = "reminder.endHour"
        static let endMinute = "reminder.endMinute"
        static let interval = "reminder.repeatInterval"
    }

    static let intervalChoices = [15, 30, 60, 120, 180]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        let base = DailyReminderSettings()
        defaults.register(defaults: [
            Key.enabled: base.isEnabled, Key.hour: base.hour, Key.minute: base.minute,
            Key.endHour: base.endHour, Key.endMinute: base.endMinute, Key.interval: base.repeatInterval,
        ])
    }

    static func load(_ defaults: UserDefaults = .standard) -> DailyReminderSettings {
        let stored = defaults.integer(forKey: Key.interval)
        // Older builds offered 5 / 10 min; snap to the closest choice the picker can show.
        let interval = intervalChoices.min { abs($0 - stored) < abs($1 - stored) } ?? 60
        return DailyReminderSettings(
            isEnabled: defaults.bool(forKey: Key.enabled),
            hour: min(max(defaults.integer(forKey: Key.hour), 0), 23),
            minute: min(max(defaults.integer(forKey: Key.minute), 0), 59),
            endHour: min(max(defaults.integer(forKey: Key.endHour), 0), 23),
            endMinute: min(max(defaults.integer(forKey: Key.endMinute), 0), 59),
            repeatInterval: interval
        )
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(hour, forKey: Key.hour)
        defaults.set(minute, forKey: Key.minute)
        defaults.set(endHour, forKey: Key.endHour)
        defaults.set(endMinute, forKey: Key.endMinute)
        defaults.set(repeatInterval, forKey: Key.interval)
    }

    /// Repeats only run when the end time is after the summary time.
    var hasRepeatWindow: Bool { endHour * 60 + endMinute > hour * 60 + minute }

    func start(of day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    func end(of day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day)
    }
}

/// Open tasks as seen on one day.
struct DayAgenda: Equatable {
    /// Due before `day`.
    let overdue: [Task]
    /// Due on `day`.
    let dueToday: [Task]
    /// Not due yet, but planned (do date) for `day` or an earlier day.
    let doToday: [Task]
    /// Planned or due within the next week — listed so you know what's coming.
    let upcoming: [Task]
    /// No do date and no due date: always listed until done, never repeated.
    let undated: [Task]

    init(tasks: [Task], day: Date, calendar: Calendar = .current) {
        let open = tasks.filter { !$0.completed }
        let weekOut = calendar.date(byAdding: .day, value: 7, to: day) ?? day
        overdue = open.filter { ($0.dueDay ?? .distantFuture) < day }.sorted(by: TaskSort.byDateThenPriority)
        dueToday = open.filter { $0.dueDay == day }.sorted(by: TaskSort.byPriority)
        let notDue = open.filter { ($0.dueDay ?? .distantFuture) > day }
        doToday = notDue.filter { ($0.scheduledDay ?? .distantFuture) <= day }.sorted(by: TaskSort.byPriority)
        upcoming = notDue.filter { task in
            guard let plan = task.planDay else { return false }
            return plan > day && plan <= weekOut
        }
        .sorted(by: TaskSort.byDateThenPriority)
        undated = open.filter { $0.planDay == nil }.sorted(by: TaskSort.byPriority)
    }

    /// Due today or overdue: these get repeated reminders until they're done.
    var pressing: [Task] { overdue + dueToday }
    var all: [Task] { overdue + dueToday + doToday + upcoming + undated }
    var isEmpty: Bool { all.isEmpty }
}

/// One notification to schedule.
struct DailyReminder: Equatable {
    enum Kind: String {
        /// Once a day: everything still open, with deadlines.
        case summary
        /// Repeats through the day while something is due or overdue.
        case nag
    }

    let kind: Kind
    /// `YYYY-MM-DD` of the day it's about.
    let dayKey: String
    let fireDate: Date
    let title: String
    let subtitle: String?
    let body: String
    /// Set when the reminder is about exactly one task, so it can offer "Mark as Done".
    let taskID: Int?

    var identifier: String {
        "\(DailyReminderPlanner.identifierPrefix)\(dayKey).\(kind.rawValue).\(Int(fireDate.timeIntervalSince1970))"
    }
}

/// Decides which reminder notifications should exist, given the tasks and settings.
///
/// - Every day at the summary time: a list of what's open — overdue, due today, due this week
///   and tasks without a due date — each with its deadline.
/// - Tasks that are due today or overdue repeat every `repeatInterval` minutes until the end
///   time, and keep doing so each day until they're marked done.
enum DailyReminderPlanner {
    static let identifierPrefix = "taskwidget.daily."
    /// Summaries are scheduled a week ahead so they still fire if the app isn't running.
    static let daysAhead = 7
    /// Repeats are scheduled for today and tomorrow; the app tops them up while it runs.
    static let repeatDays = 2
    /// macOS keeps at most 64 pending notifications per app; leave room for tests.
    static let maxPending = 60
    private static let maxListed = 6

    /// - Parameters:
    ///   - snoozedUntil: repeats before this moment are skipped.
    ///   - summaryDeliveredToday: false when today's summary time passed without one being
    ///     scheduled (the app wasn't running yet); a catch-up summary is then sent right away.
    static func plan(tasks: [Task], settings: DailyReminderSettings, snoozedUntil: Date? = nil,
                     summaryDeliveredToday: Bool = true,
                     now: Date = Date(), calendar: Calendar = .current) -> [DailyReminder] {
        guard settings.isEnabled else { return [] }
        let today = calendar.startOfDay(for: now)
        var summaries: [DailyReminder] = []
        var nags: [DailyReminder] = []

        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = settings.start(of: day, calendar: calendar),
                  let end = settings.end(of: day, calendar: calendar) else { continue }
            let agenda = DayAgenda(tasks: tasks, day: day, calendar: calendar)
            guard !agenda.isEmpty else { continue }
            let dayKey = TaskDate.string(from: day)

            if start > now {
                summaries.append(summary(agenda, dayKey: dayKey, day: day, at: start, calendar: calendar))
            } else if offset == 0 && !summaryDeliveredToday && (now < end || !settings.hasRepeatWindow) {
                summaries.append(summary(agenda, dayKey: dayKey, day: day, at: now, calendar: calendar))
            }

            guard offset < repeatDays, !agenda.pressing.isEmpty, settings.hasRepeatWindow else { continue }
            let step = TimeInterval(settings.repeatInterval * 60)
            var fire = start.addingTimeInterval(step)
            while fire <= end {
                if fire > now && snoozedUntil.map({ fire >= $0 }) ?? true {
                    nags.append(nag(agenda, dayKey: dayKey, day: day, at: fire, calendar: calendar))
                }
                fire.addTimeInterval(step)
            }
        }
        // Summaries first (at most one a day), then the soonest repeats that still fit.
        return summaries + nags.sorted { $0.fireDate < $1.fireDate }.prefix(max(0, maxPending - summaries.count))
    }

    // MARK: - Content

    static func summary(_ agenda: DayAgenda, dayKey: String, day: Date, at fire: Date,
                        calendar: Calendar = .current) -> DailyReminder {
        let count = agenda.all.count
        var counts: [String] = []
        if !agenda.overdue.isEmpty { counts.append("\(agenda.overdue.count) overdue") }
        if !agenda.dueToday.isEmpty { counts.append("\(agenda.dueToday.count) due today") }
        if !agenda.doToday.isEmpty { counts.append("\(agenda.doToday.count) planned today") }
        if !agenda.upcoming.isEmpty { counts.append("\(agenda.upcoming.count) this week") }
        if !agenda.undated.isEmpty { counts.append("\(agenda.undated.count) no deadline") }
        return DailyReminder(
            kind: .summary, dayKey: dayKey, fireDate: fire,
            title: "Today: \(count) \(count == 1 ? "task" : "tasks") to do",
            subtitle: counts.joined(separator: " · "),
            body: lines(agenda.all, day: day, calendar: calendar),
            taskID: agenda.all.count == 1 ? agenda.all.first?.id : nil
        )
    }

    static func nag(_ agenda: DayAgenda, dayKey: String, day: Date, at fire: Date,
                    calendar: Calendar = .current) -> DailyReminder {
        let pressing = agenda.pressing
        if pressing.count == 1, let task = pressing.first {
            let project = task.project.isEmpty ? "" : " · \(task.project)"
            return DailyReminder(
                kind: .nag, dayKey: dayKey, fireDate: fire,
                title: "\(dot(for: task)) \(task.title)",
                subtitle: timing(for: task, on: day, calendar: calendar).capitalizedFirst,
                body: "\(task.priority.displayName) priority\(project) — repeats until it's done.",
                taskID: task.id
            )
        }
        let title: String
        switch (agenda.dueToday.count, agenda.overdue.count) {
        case (0, let o): title = "\(o) overdue tasks still open"
        case (let d, 0): title = "\(d) tasks due today still open"
        case (let d, let o): title = "\(d + o) tasks still open (\(o) overdue)"
        }
        return DailyReminder(
            kind: .nag, dayKey: dayKey, fireDate: fire, title: title,
            subtitle: "Repeats until they're done",
            body: lines(pressing, day: day, calendar: calendar), taskID: nil
        )
    }

    /// "🔴 Fix bug — wms · due today", one per task, capped with "+N more".
    static func lines(_ tasks: [Task], day: Date, calendar: Calendar = .current) -> String {
        var lines = tasks.prefix(maxListed).map { line(for: $0, day: day, calendar: calendar) }
        if tasks.count > maxListed { lines.append("+\(tasks.count - maxListed) more") }
        return lines.joined(separator: "\n")
    }

    static func line(for task: Task, day: Date, calendar: Calendar = .current) -> String {
        let project = task.project.isEmpty ? "" : " — \(task.project)"
        return "\(dot(for: task)) \(task.title)\(project) · \(timing(for: task, on: day, calendar: calendar))"
    }

    /// When to work on it and when it's due: "do today · due Fri (in 3 days)". Without a do
    /// date it's just the deadline ("no deadline" when there's neither).
    static func timing(for task: Task, on day: Date, calendar: Calendar = .current) -> String {
        guard let planned = Self.plan(for: task, on: day, calendar: calendar) else {
            return deadline(for: task, on: day, calendar: calendar)
        }
        return task.dueDay == nil ? planned : "\(planned) · \(deadline(for: task, on: day, calendar: calendar))"
    }

    /// "do today", "do today (planned Mon)", "do Wed (in 2 days)", "do 20 Oct"; nil when unplanned.
    static func plan(for task: Task, on day: Date, calendar: Calendar = .current) -> String? {
        guard let scheduled = task.scheduledDay else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: scheduled).day ?? 0
        switch days {
        case 0: return "do today"
        case 1: return "do tomorrow"
        case 2...6: return "do \(weekday.string(from: scheduled)) (in \(days) days)"
        case 7...: return "do \(shortDate.string(from: scheduled))"
        default: return "do today (planned \(shortDate.string(from: scheduled)))"
        }
    }

    /// Dots match the priority colours used in the app and widget.
    static func dot(for task: Task) -> String {
        switch task.priority {
        case .high: return "🔴"
        case .medium: return "🟡"
        case .low: return "🔵"
        }
    }

    /// When it has to be done by, relative to `day`: "due today", "due Fri (in 3 days)",
    /// "overdue 2 days", "no deadline".
    static func deadline(for task: Task, on day: Date, calendar: Calendar = .current) -> String {
        guard let due = task.dueDay else { return "no deadline" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: due).day ?? 0
        switch days {
        case 0: return "due today"
        case 1: return "due tomorrow"
        case 2...6: return "due \(weekday.string(from: due)) (in \(days) days)"
        case 7...: return "due \(shortDate.string(from: due))"
        case -1: return "overdue since yesterday"
        default: return "overdue \(-days) days (was due \(shortDate.string(from: due)))"
        }
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
