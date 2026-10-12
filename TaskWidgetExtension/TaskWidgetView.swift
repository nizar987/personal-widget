import WidgetKit
import SwiftUI

/// Rows that fit on one page for each size.
private enum RowsPerPage {
    static let small = 3
    static let medium = 3
    static let large = 8
}

struct TaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskProvider.Entry

    var body: some View {
        Group {
            if entry.errorMessage != nil && entry.tasks.isEmpty {
                OfflineTile()
            } else {
                switch family {
                case .systemSmall: SmallLayout(entry: entry, scope: family.stateScope)
                case .systemMedium: MediumLayout(entry: entry, scope: family.stateScope)
                default: LargeLayout(entry: entry, scope: family.stateScope)
                }
            }
        }
        .padding(WidgetTheme.outerPadding)
        // Only the ↗ button opens the app; other clicks land on a no-op control.
        .modifier(SwallowClicks())
        .containerBackground(WidgetTheme.background, for: .widget)
    }
}

// MARK: - Small: one list, tap the title to switch lists

struct SmallLayout: View {
    let entry: TaskEntry
    let scope: String

    var body: some View {
        let model = WidgetListModel(tasks: entry.tasks, tab: entry.state.tab, page: entry.state.page,
                                    rowsPerPage: RowsPerPage.small, now: entry.date)
        VStack(alignment: .leading, spacing: 7) {
            ListHeader(tab: model.tab, count: model.total, scope: scope, cycles: true)
            TaskListBody(model: model, now: entry.date, compact: true)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                AddTaskButton()
                OpenAppButton()
                Spacer(minLength: 2)
                Pager(page: model.page, pageCount: model.pageCount, scope: scope)
            }
        }
        .tile()
    }
}

// MARK: - Medium: today's progress + tabbed list

struct MediumLayout: View {
    let entry: TaskEntry
    let scope: String

    var body: some View {
        let model = WidgetListModel(tasks: entry.tasks, tab: entry.state.tab, page: entry.state.page,
                                    rowsPerPage: RowsPerPage.medium, now: entry.date)
        HStack(spacing: WidgetTheme.tileSpacing) {
            VStack(spacing: 6) {
                VStack(spacing: 0) {
                    Text(entry.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.todayAccent)
                    Text(entry.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                ProgressRing(progress: DayProgress(tasks: entry.tasks, now: entry.date), size: 56)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    OpenAppButton()
                    AddTaskButton(label: "New")
                }
            }
            .frame(maxWidth: .infinity)
            .tile(padding: 8)
            .frame(width: 104)

            VStack(alignment: .leading, spacing: 7) {
                TabBar(selected: model.tab, tasks: entry.tasks, now: entry.date, scope: scope, compact: true)
                TaskListBody(model: model, now: entry.date, showsSnooze: true)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Pager(page: model.page, pageCount: model.pageCount, scope: scope)
                }
            }
            .tile()
        }
    }
}

// MARK: - Large: header, tappable week, tabbed list

struct LargeLayout: View {
    let entry: TaskEntry
    let scope: String

    var body: some View {
        let model = WidgetListModel(tasks: entry.tasks, tab: entry.state.tab, page: entry.state.page,
                                    rowsPerPage: RowsPerPage.large, now: entry.date)
        let progress = DayProgress(tasks: entry.tasks, now: entry.date)
        VStack(spacing: WidgetTheme.tileSpacing) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.todayAccent)
                    Text(entry.date, format: .dateTime.month(.wide).day())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                Spacer()
                ProgressRing(progress: progress, size: 34)
                OpenAppButton()
                AddTaskButton(label: "New")
            }
            .padding(.horizontal, 4)

            WeekStrip(tasks: entry.tasks, now: entry.date, selected: model.tab, scope: scope)
                .frame(height: 62)

            VStack(alignment: .leading, spacing: 8) {
                TabBar(selected: model.tab, tasks: entry.tasks, now: entry.date, scope: scope)
                TaskListBody(model: model, now: entry.date, showsSnooze: true)
                Spacer(minLength: 0)
                HStack {
                    Text(footer(model))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Pager(page: model.page, pageCount: model.pageCount, scope: scope)
                }
            }
            .tile()
        }
    }

    private func footer(_ model: WidgetListModel) -> String {
        model.total == 0 ? "" : "\(model.total) open in \(model.tab.title)"
    }
}

// MARK: - Widget

@main
struct TaskWidgetExtensionWidget: Widget {
    let kind: String = "com.multiagent.taskwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            TaskWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks")
        .description("Check off, snooze and browse your tasks right from the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview("Small", as: .systemSmall) {
    TaskWidgetExtensionWidget()
} timeline: {
    TaskEntry.sample
}

#Preview("Medium", as: .systemMedium) {
    TaskWidgetExtensionWidget()
} timeline: {
    TaskEntry.sample
}

#Preview("Large", as: .systemLarge) {
    TaskWidgetExtensionWidget()
} timeline: {
    TaskEntry.sample
    TaskEntry(date: Date(), tasks: [], errorMessage: "offline")
}
