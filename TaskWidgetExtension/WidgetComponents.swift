import SwiftUI
import WidgetKit

// MARK: - Surfaces

struct TileBackground: ViewModifier {
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: WidgetTheme.tileRadius, style: .continuous)
                    .fill(WidgetTheme.tile)
            )
    }
}

extension View {
    func tile(padding: CGFloat = 10) -> some View { modifier(TileBackground(padding: padding)) }
}

struct CountBadge: View {
    let count: Int
    let accent: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(count)))
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(Capsule().fill(accent == .gray ? Color.gray : accent))
            .widgetAccentable()
    }
}

// MARK: - Task row

struct TaskRow: View {
    let task: Task
    let now: Date
    var showsDue = true
    var hidesTodayLabel = false
    var showsSnooze = false
    /// Small widget: no room for "Overdue" / "Tmrw", so only overdue gets a tiny marker.
    var compact = false

    private var dueLabel: String? {
        guard showsDue, let label = DueLabel.text(for: task, now: now) else { return nil }
        return hidesTodayLabel && label == "Today" ? nil : label
    }

    /// Snoozing makes sense for open tasks that are due now (today or overdue).
    private var canSnooze: Bool { showsSnooze && !task.completed && task.isDueByToday(now) }

    var body: some View {
        HStack(spacing: 4) {
            // Toggle(isOn:intent:) flips to "checked" instantly, before the intent finishes.
            Toggle(isOn: task.completed, intent: ToggleTaskIntent(taskId: task.id)) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    if compact {
                        if task.isOverdue(now) && !task.completed {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(WidgetTheme.todayAccent)
                        }
                    } else if let label = dueLabel, !task.completed {
                        Text(label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(DueLabel.color(for: task, now: now))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .toggleStyle(CheckCircleToggleStyle(tint: WidgetTheme.color(for: task.priority)))

            if canSnooze {
                Button(intent: SnoozeTaskIntent(taskId: task.id)) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 16)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Move to tomorrow")
            }
        }
    }
}

/// LockDay-style ring that fills with a checkmark and strikes through the label.
struct CheckCircleToggleStyle: ToggleStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(configuration.isOn ? Palette.done : tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 13, height: 13)
            configuration.label
                .foregroundStyle(configuration.isOn ? .secondary : .primary)
                .strikethrough(configuration.isOn, color: .secondary)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: configuration.isOn)
    }
}

/// Rows slide up into place when added and slide away when completed.
extension AnyTransition {
    static var taskRow: AnyTransition {
        .asymmetric(
            insertion: .push(from: .bottom).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Task list (rows + empty state)

struct TaskListBody: View {
    let model: WidgetListModel
    let now: Date
    var showsSnooze = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if model.rows.isEmpty {
                EmptyListLine(tab: model.tab)
            } else {
                ForEach(model.rows, id: \.id) { task in
                    TaskRow(task: task, now: now, showsDue: !model.tab.isDay,
                            hidesTodayLabel: model.tab == .today, showsSnooze: showsSnooze, compact: compact)
                        .transition(.taskRow)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.rows.map(\.id))
    }
}

private struct EmptyListLine: View {
    let tab: WidgetTab

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab == .today ? "checkmark.seal.fill" : "sparkles")
                .foregroundStyle(tab == .today ? Palette.done : .secondary)
            Text(tab == .today ? "All clear today" : "Nothing here")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.top, 2)
    }
}

// MARK: - Header, tabs, pager

/// Tab title with count. When `cycles`, tapping it switches to the next tab (small widget).
struct ListHeader: View {
    let tab: WidgetTab
    let count: Int
    let scope: String
    var cycles = false

    var body: some View {
        if cycles {
            Button(intent: SelectWidgetTabIntent(scope: scope, tab: tab.next)) { label(showsChevron: true) }
                .buttonStyle(.plain)
        } else {
            label(showsChevron: false)
        }
    }

    private func label(showsChevron: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: tab.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tab.accent)
                .widgetAccentable()
            Text(tab.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tab.accent == .gray ? Color.primary : tab.accent)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            CountBadge(count: count, accent: tab.accent)
        }
        .contentShape(Rectangle())
    }
}

/// Pill buttons that switch the visible list.
struct TabBar: View {
    let selected: WidgetTab
    let tasks: [Task]
    let now: Date
    let scope: String
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WidgetTab.fixed, id: \.rawValue) { tab in
                pill(tab)
            }
            if case .day = selected {
                pill(selected)
            }
        }
    }

    private var useShortTitles: Bool {
        if compact { return true }
        if case .day = selected { return true }
        return false
    }

    private func pill(_ tab: WidgetTab) -> some View {
        let isOn = tab == selected
        let compact = useShortTitles
        let count = WidgetListModel.count(for: tab, in: tasks, now: now)
        return Button(intent: SelectWidgetTabIntent(scope: scope, tab: tab)) {
            HStack(spacing: 3) {
                if !compact || isOn {
                    Image(systemName: tab.icon).font(.system(size: 8.5, weight: .bold))
                }
                Text(compact ? tab.shortTitle : tab.title)
                if count > 0 {
                    Text("\(count)").monospacedDigit().opacity(0.75)
                }
            }
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(isOn ? tab.accent : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(isOn ? tab.accent.opacity(0.18) : Color.primary.opacity(0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .widgetAccentable(isOn)
    }
}

/// ‹ 1/3 › — wraps around at both ends.
struct Pager: View {
    let page: Int
    let pageCount: Int
    let scope: String

    var body: some View {
        if pageCount > 1 {
            HStack(spacing: 6) {
                arrow("chevron.left", to: (page - 1 + pageCount) % pageCount)
                Text("\(page + 1)/\(pageCount)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                arrow("chevron.right", to: (page + 1) % pageCount)
            }
        }
    }

    private func arrow(_ icon: String, to target: Int) -> some View {
        Button(intent: ChangeWidgetPageIntent(scope: scope, page: target)) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 15)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The only way to open the main window from the widget (clicks elsewhere are swallowed).
struct OpenAppButton: View {
    var body: some View {
        Link(destination: AppLink.open.url) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .help("Open TaskWidget")
    }
}

/// Fills the widget's empty space with a no-op control so clicks there don't open the app.
struct SwallowClicks: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            Button(intent: WidgetNoOpIntent()) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        )
    }
}

/// Opens quick capture in the app.
struct AddTaskButton: View {
    var label: String?

    var body: some View {
        Link(destination: AppLink.quickCapture.url) {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                if let label {
                    Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, label == nil ? 0 : 7)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Color.accentColor))
            .widgetAccentable()
        }
    }
}

/// Ring with "done/total" for today.
struct ProgressRing: View {
    let progress: DayProgress
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(Palette.done, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: -1) {
                Text("\(progress.done)/\(progress.total)")
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(progress.done)))
                Text("done")
                    .font(.system(size: size * 0.15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress.done)
    }
}

// MARK: - Next 7 days (large widget; days are tappable)

struct WeekStrip: View {
    let tasks: [Task]
    let now: Date
    let selected: WidgetTab
    let scope: String

    /// Rolling window starting today, so every day shown can still be planned.
    private var days: [Date] {
        (0..<7).map { TaskDate.day(offset: $0, from: now) }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                dayButton(day)
            }
        }
        .tile(padding: 6)
    }

    private func dayButton(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDate(day, inSameDayAs: now)
        let isSelected: Bool = {
            if case .day(let d) = selected { return d == day }
            return isToday && selected == .today
        }()
        let dayTasks = tasks.filter { !$0.completed && $0.planDay == day }
        // Today maps to the Today list, which also includes overdue tasks.
        let target: WidgetTab = isToday ? .today : .day(day)

        return Button(intent: SelectWidgetTabIntent(scope: scope, tab: target)) {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? WidgetTheme.background : .primary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(isToday ? Color.primary : .clear))
                HStack(spacing: 2) {
                    ForEach(dayTasks.prefix(3), id: \.id) { task in
                        Circle().fill(WidgetTheme.color(for: task.priority)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Offline / error state

struct OfflineTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WidgetTheme.upcomingAccent)
            Text("Backend offline")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Start the TaskWidget server on \(Constants.apiHostLabel). Retrying in 5 min.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .tile()
    }
}
