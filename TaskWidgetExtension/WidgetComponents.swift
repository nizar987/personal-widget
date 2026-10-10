import SwiftUI
import WidgetKit

// MARK: - Tile container

struct TileBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: WidgetTheme.tileRadius, style: .continuous)
                    .fill(WidgetTheme.tile)
            )
    }
}

extension View {
    func tile() -> some View { modifier(TileBackground()) }
}

// MARK: - Header + badge

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
            .background(Capsule().fill(accent == .primary ? Color.gray : accent))
            .widgetAccentable()
    }
}

struct SectionHeader: View {
    let section: TaskSection

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: section.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(section.accent)
                .widgetAccentable()
            Text(section.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(section.accent == .secondary ? Color.primary : section.accent)
                .lineLimit(1)
            Spacer(minLength: 4)
            CountBadge(count: section.tasks.count, accent: section.accent)
        }
    }
}

// MARK: - Task row

struct TaskRow: View {
    let task: Task
    let now: Date
    var showsDue = true
    var hidesTodayLabel = false

    private var dueLabel: String? {
        guard showsDue, let label = DueLabel.text(for: task, now: now) else { return nil }
        return hidesTodayLabel && label == "Today" ? nil : label
    }

    var body: some View {
        // Toggle(isOn:intent:) flips to "checked" instantly, before the intent finishes.
        Toggle(isOn: task.completed, intent: ToggleTaskIntent(taskId: task.id)) {
            HStack(spacing: 6) {
                Text(task.title)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                if let label = dueLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(DueLabel.color(for: task, now: now))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .toggleStyle(CheckCircleToggleStyle(tint: WidgetTheme.color(for: task.priority)))
    }
}

/// LockDay-style ring that fills with a checkmark and strikes through the label.
struct CheckCircleToggleStyle: ToggleStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint)
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

// MARK: - Section tile (header + rows + "+N more")

struct SectionTile: View {
    let section: TaskSection
    let now: Date
    let maxRows: Int
    var showsDue = true
    var hidesTodayLabel = false
    var emptyText = "Nothing here"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(section: section)
            if section.tasks.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(section.tasks.prefix(maxRows), id: \.id) { task in
                    TaskRow(task: task, now: now, showsDue: showsDue, hidesTodayLabel: hidesTodayLabel)
                        .transition(.taskRow)
                }
                if section.tasks.count > maxRows {
                    Text("+\(section.tasks.count - maxRows) more")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(section.tasks.count)))
                        .padding(.leading, 19)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: section.tasks.map(\.id))
        .tile()
    }
}

// MARK: - Week strip

struct WeekStrip: View {
    let tasks: [Task]
    let now: Date

    private var days: [Date] {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                DayColumn(day: day, tasks: tasks(on: day), isToday: Calendar.current.isDate(day, inSameDayAs: now))
            }
        }
        .tile()
    }

    private func tasks(on day: Date) -> [Task] {
        tasks.filter { t in t.dueDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { $0.priority.rank > $1.priority.rank }
    }
}

private struct DayColumn: View {
    let day: Date
    let tasks: [Task]
    let isToday: Bool

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    var body: some View {
        VStack(spacing: 3) {
            Text(Self.weekday.string(from: day))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? WidgetTheme.background : .primary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isToday ? Color.primary : .clear))
            VStack(spacing: 2) {
                ForEach(tasks.prefix(2), id: \.id) { t in
                    Text(t.title)
                        .font(.system(size: 7.5, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(WidgetTheme.color(for: t.priority).opacity(0.35))
                        )
                }
                if tasks.count > 2 {
                    Text("+\(tasks.count - 2)")
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mini month calendar

struct MiniMonth: View {
    let tasks: [Task]
    let now: Date

    private var cal: Calendar { Calendar.current }

    private var monthTitle: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: now)
    }

    /// Leading nils pad the first week so day 1 lands on its weekday column.
    private var cells: [Date?] {
        guard let month = cal.dateInterval(of: .month, for: now),
              let count = cal.range(of: .day, in: .month, for: now)?.count else { return [] }
        let lead = (cal.component(.weekday, from: month.start) - cal.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: month.start) }
        return Array(repeating: nil, count: lead) + days.map { Optional($0) }
    }

    private var symbols: [String] {
        let s = cal.veryShortWeekdaySymbols
        let i = cal.firstWeekday - 1
        return Array(s[i...] + s[..<i])
    }

    private var busyDays: Set<Int> {
        Set(tasks.compactMap { t in
            guard let d = t.dueDay, cal.isDate(d, equalTo: now, toGranularity: .month) else { return nil }
            return cal.component(.day, from: d)
        })
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(alignment: .leading, spacing: 4) {
            Text(monthTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.todayAccent)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(.tertiary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }
            Spacer(minLength: 0)
        }
        .tile()
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let n = cal.component(.day, from: day)
            let isToday = cal.isDate(day, inSameDayAs: now)
            Text("\(n)")
                .font(.system(size: 8.5, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(isToday ? WidgetTheme.background : (busyDays.contains(n) ? .primary : .secondary))
                .frame(width: 14, height: 14)
                .background(Circle().fill(isToday ? Color.primary : .clear))
                .overlay(alignment: .bottom) {
                    if busyDays.contains(n) && !isToday {
                        Circle().fill(WidgetTheme.todayAccent).frame(width: 2.5, height: 2.5).offset(y: 2)
                    }
                }
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
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
