import SwiftUI

/// Month grid with task chips per day. Chips can be dragged onto another day to reschedule.
struct MonthGridView: View {
    let month: Date
    let tasks: [Task]
    @Binding var selectedDay: Date
    let onOpenTask: (Task) -> Void
    let onReschedule: (Task, Date) -> Void

    @State private var gridWidth: CGFloat = 0
    /// Below this cell width chips can't show readable titles, so every cell uses dots.
    private let minChipCellWidth: CGFloat = 78

    private var cal: Calendar { .current }
    private var isCompact: Bool { gridWidth > 0 && gridWidth / 7 < minChipCellWidth }

    /// 6×7 days covering the month, padded with neighbouring months.
    private var days: [Date] {
        guard let monthStart = cal.dateInterval(of: .month, for: month)?.start else { return [] }
        let lead = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -lead, to: monthStart) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.shortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var tasksByDay: [Date: [Task]] {
        Dictionary(grouping: tasks.filter { $0.dueDay != nil }) { $0.dueDay ?? .distantPast }
            .mapValues { $0.sorted { ($0.completed ? 1 : 0, -$0.priority.rank) < ($1.completed ? 1 : 0, -$1.priority.rank) } }
    }

    var body: some View {
        let byDay = tasksByDay
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    DayCell(
                        day: day,
                        tasks: byDay[day] ?? [],
                        isInMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                        isToday: cal.isDateInToday(day),
                        isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                        isCompact: isCompact,
                        onSelect: { withAnimation(AppStyle.spring) { selectedDay = day } },
                        onOpenTask: onOpenTask,
                        onDropTask: { id in
                            guard let task = tasks.first(where: { $0.id == id }) else { return false }
                            onReschedule(task, day)
                            return true
                        }
                    )
                }
            }
            .background(GeometryReader { geo in
                Color.clear.preference(key: GridWidthKey.self, value: geo.size.width)
            })
            .onPreferenceChange(GridWidthKey.self) { gridWidth = $0 }
        }
    }
}

private struct GridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct DayCell: View {
    let day: Date
    let tasks: [Task]
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isCompact: Bool
    let onSelect: () -> Void
    let onOpenTask: (Task) -> Void
    let onDropTask: (Int) -> Bool

    @State private var isDropTarget = false
    private let maxChips = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isToday ? Color.white : (isInMonth ? Color.primary : Color.secondary))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(isToday ? Palette.today : .clear))
                Spacer(minLength: 0)
                if tasks.count > (isCompact ? 5 : maxChips) {
                    Text("+\(tasks.count - (isCompact ? 5 : maxChips))")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            // Wide cells show titled chips; narrow cells fall back to coloured dots.
            if !isCompact {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(tasks.prefix(maxChips), id: \.id) { task in
                        TaskChip(task: task)
                            .onTapGesture { onOpenTask(task) }
                            .draggable(String(task.id)) { TaskChip(task: task).frame(width: 120) }
                    }
                }
            } else {
                HStack(spacing: 3) {
                    ForEach(tasks.prefix(5), id: \.id) { task in
                        Circle()
                            .fill(task.completed ? Palette.done.opacity(0.5) : Palette.color(for: task.priority))
                            .frame(width: 7, height: 7)
                            .help(task.title)
                            .onTapGesture { onOpenTask(task) }
                            .draggable(String(task.id)) { TaskChip(task: task).frame(width: 120) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : (isDropTarget ? Palette.upcoming : .clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(Int.init) else { return false }
            return onDropTask(id)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) { isDropTarget = targeted }
        }
        .opacity(isInMonth ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month().day()))
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if isDropTarget { return Palette.upcoming.opacity(0.12) }
        return AppStyle.card
    }
}

/// Compact one-line task label used inside calendar cells.
struct TaskChip: View {
    let task: Task

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(task.completed ? Palette.done : Palette.color(for: task.priority))
                .frame(width: 5, height: 5)
            Text(task.title)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .strikethrough(task.completed, color: .secondary)
                .foregroundStyle(task.completed ? .secondary : .primary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill((task.completed ? Color.gray : Palette.color(for: task.priority)).opacity(0.16))
        )
        .contentShape(Rectangle())
        .help(task.title)
    }
}
