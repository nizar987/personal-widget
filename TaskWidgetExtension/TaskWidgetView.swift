import WidgetKit
import SwiftUI

struct TaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskProvider.Entry

    var body: some View {
        Group {
            if entry.errorMessage != nil && entry.tasks.isEmpty {
                OfflineTile()
            } else {
                switch family {
                case .systemSmall: SmallLayout(entry: entry)
                case .systemMedium: MediumLayout(entry: entry)
                default: LargeLayout(entry: entry)
                }
            }
        }
        .padding(WidgetTheme.outerPadding)
        .containerBackground(WidgetTheme.background, for: .widget)
    }
}

// MARK: - Small: Today (falls back to Up next when today is clear)

private struct SmallLayout: View {
    let entry: TaskEntry

    var body: some View {
        let g = entry.groups
        let section = g.today.isEmpty ? TaskSection.upNext(g) : TaskSection.today(g)
        SectionTile(section: section, now: entry.date, maxRows: 4,
                    hidesTodayLabel: true, emptyText: "All clear 🎉")
    }
}

// MARK: - Medium: month calendar + Up next

private struct MediumLayout: View {
    let entry: TaskEntry

    var body: some View {
        HStack(spacing: WidgetTheme.tileSpacing) {
            MiniMonth(tasks: entry.tasks, now: entry.date)
                .frame(width: 128)
            SectionTile(section: .upNext(entry.groups), now: entry.date, maxRows: 4,
                        emptyText: "No dated tasks")
        }
    }
}

// MARK: - Large: header, week strip, 2×2 sections

private struct LargeLayout: View {
    let entry: TaskEntry

    var body: some View {
        let g = entry.groups
        VStack(spacing: WidgetTheme.tileSpacing) {
            DateHeader(now: entry.date)
            WeekStrip(tasks: entry.tasks, now: entry.date)
                .frame(height: 74)
            Grid(horizontalSpacing: WidgetTheme.tileSpacing, verticalSpacing: WidgetTheme.tileSpacing) {
                GridRow {
                    SectionTile(section: .today(g), now: entry.date, maxRows: 3, hidesTodayLabel: true)
                    SectionTile(section: .important(g), now: entry.date, maxRows: 3)
                }
                GridRow {
                    SectionTile(section: .upcoming(g), now: entry.date, maxRows: 3)
                    SectionTile(section: .someday(g), now: entry.date, maxRows: 3, showsDue: false)
                }
            }
        }
    }
}

/// "Saturday, October 10" plus a thin year-progress bar, like LockDay's year widget.
private struct DateHeader: View {
    let now: Date

    private var yearProgress: Double {
        let cal = Calendar.current
        guard let year = cal.dateInterval(of: .year, for: now) else { return 0 }
        return now.timeIntervalSince(year.start) / year.duration
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            HStack(spacing: 6) {
                Text(now, format: .dateTime.year())
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.75)).frame(width: 54 * yearProgress)
                    }
                    .frame(width: 54, height: 4)
                Text(yearProgress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
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
        .description("Today, upcoming and someday tasks at a glance.")
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
