import SwiftUI
import WidgetKit

/// Which list the widget shows. `day` comes from tapping a date in the large widget's week strip.
enum WidgetTab: Equatable {
    case today, upcoming, important, someday
    case day(Date)

    static let fixed: [WidgetTab] = [.today, .upcoming, .important, .someday]

    var title: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .important: return "Important"
        case .someday: return "Someday"
        case .day(let date): return date.formatted(.dateTime.weekday(.abbreviated).day())
        }
    }

    /// Short label for the medium widget's tab bar.
    var shortTitle: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Next"
        case .important: return "Star"
        case .someday: return "Later"
        case .day: return title
        }
    }

    var icon: String {
        switch self {
        case .today: return "flame.fill"
        case .upcoming: return "bolt.fill"
        case .important: return "star.fill"
        case .someday: return "tray.fill"
        case .day: return "calendar"
        }
    }

    var accent: Color {
        switch self {
        case .today: return WidgetTheme.todayAccent
        case .upcoming: return WidgetTheme.upcomingAccent
        case .important: return WidgetTheme.importantAccent
        case .someday: return .gray
        case .day: return WidgetTheme.upcomingAccent
        }
    }

    /// Stored form: `today`, `upcoming`, … or `day:YYYY-MM-DD`.
    var rawValue: String {
        switch self {
        case .today: return "today"
        case .upcoming: return "upcoming"
        case .important: return "important"
        case .someday: return "someday"
        case .day(let date): return "day:\(TaskDate.string(from: date))"
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "upcoming": self = .upcoming
        case "important": self = .important
        case "someday": self = .someday
        case let raw where raw.hasPrefix("day:"):
            self = TaskDate.date(from: String(raw.dropFirst(4))).map(WidgetTab.day) ?? .today
        default: self = .today
        }
    }

    var isDay: Bool {
        if case .day = self { return true }
        return false
    }

    var next: WidgetTab {
        guard let index = Self.fixed.firstIndex(of: self) else { return .today }
        return Self.fixed[(index + 1) % Self.fixed.count]
    }
}

/// Per-size widget state. Intents run in the extension process, so plain UserDefaults is shared
/// between the buttons (writers) and the timeline provider (reader).
struct WidgetUIState: Equatable {
    var tab: WidgetTab = .today
    var page = 0

    private static func key(_ scope: String, _ field: String) -> String { "widget.\(scope).\(field)" }

    static func load(scope: String, defaults: UserDefaults = .standard) -> WidgetUIState {
        WidgetUIState(tab: WidgetTab(rawValue: defaults.string(forKey: key(scope, "tab")) ?? "today"),
                      page: max(defaults.integer(forKey: key(scope, "page")), 0))
    }

    func save(scope: String, defaults: UserDefaults = .standard) {
        defaults.set(tab.rawValue, forKey: Self.key(scope, "tab"))
        defaults.set(page, forKey: Self.key(scope, "page"))
    }

    /// A tapped day that has passed falls back to Today.
    func normalized(now: Date) -> WidgetUIState {
        guard case .day(let date) = tab, date < Calendar.current.startOfDay(for: now) else { return self }
        return WidgetUIState(tab: .today, page: 0)
    }
}

extension WidgetFamily {
    /// Key for per-size state ("small", "medium", "large").
    var stateScope: String {
        switch self {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        default: return "large"
        }
    }
}

/// What a widget list shows: rows for the current page plus paging and progress info.
struct WidgetListModel {
    let tab: WidgetTab
    let rows: [Task]
    let page: Int
    let pageCount: Int
    let total: Int

    init(tasks: [Task], tab: WidgetTab, page: Int, rowsPerPage: Int, now: Date) {
        let all = Self.tasks(for: tab, in: tasks, now: now)
        let pages = max(1, Int((Double(all.count) / Double(max(rowsPerPage, 1))).rounded(.up)))
        let current = min(page, pages - 1)
        self.tab = tab
        self.rows = Array(all.dropFirst(current * rowsPerPage).prefix(rowsPerPage))
        self.page = current
        self.pageCount = pages
        self.total = all.filter { !$0.completed }.count
    }

    /// Open tasks first; done-today tasks stay visible (struck through) so a mis-tap can be undone.
    static func tasks(for tab: WidgetTab, in tasks: [Task], now: Date) -> [Task] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let open = tasks.filter { !$0.completed }
        let doneToday = tasks.filter { $0.completedDate.map { cal.isDate($0, inSameDayAs: now) } ?? false }

        switch tab {
        case .today:
            return open.filter { $0.isPlannedByToday(now) }.sorted(by: TaskSort.byDateThenPriority)
                + doneToday.filter { ($0.planDay ?? .distantFuture) <= today }
        case .upcoming:
            return open.filter { ($0.planDay ?? .distantPast) > today }.sorted(by: TaskSort.byDateThenPriority)
        case .important:
            return open.filter { $0.priority == .high }.sorted(by: TaskSort.byDateThenPriority)
                + doneToday.filter { $0.priority == .high }
        case .someday:
            return open.filter { $0.planDay == nil }.sorted(by: TaskSort.byPriority)
        case .day(let date):
            let onDay = tasks.filter { $0.planDay == date }
            return onDay.filter { !$0.completed }.sorted(by: TaskSort.byPriority) + onDay.filter(\.completed)
        }
    }

    static func count(for tab: WidgetTab, in tasks: [Task], now: Date) -> Int {
        Self.tasks(for: tab, in: tasks, now: now).filter { !$0.completed }.count
    }
}

/// Today's progress: tasks done today vs. still due today or overdue.
struct DayProgress {
    let done: Int
    let total: Int

    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    init(tasks: [Task], now: Date) {
        let cal = Calendar.current
        done = tasks.filter { $0.completedDate.map { cal.isDate($0, inSameDayAs: now) } ?? false }.count
        total = done + tasks.filter { !$0.completed && $0.isPlannedByToday(now) }.count
    }
}
