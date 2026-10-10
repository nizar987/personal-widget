import SwiftUI
import Charts

/// Weekly summary: stats, daily activity chart, breakdowns, and the tasks behind them.
struct WeeklyReportView: View {
    let store: TaskStore
    @Binding var weekStart: Date
    @Binding var selectedTaskID: Int?

    @State private var pendingDelete: Task?

    private var report: WeeklyReport { WeeklyReport(tasks: store.tasks, weekStart: weekStart) }
    private var isCurrentWeek: Bool { weekStart == WeekRange.start(of: Date()) }

    var body: some View {
        let report = report
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stats(report)
                ReportChartCard(daily: report.daily)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { breakdowns(report) }
                    VStack(spacing: 16) { breakdowns(report) }
                }
                completedList(report)
                taskCard(title: "Still open this week", icon: "arrow.uturn.forward.circle.fill",
                         accent: Palette.upcoming, tasks: report.carriedOver,
                         emptyText: "Everything due this week is done 🎉")
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .animation(AppStyle.spring, value: weekStart)
        }
        .confirmationDialog("Delete “\(pendingDelete?.title ?? "")”?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let task = pendingDelete else { return }
                if selectedTaskID == task.id { selectedTaskID = nil }
                _Concurrency.Task { await store.delete(task) }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: - Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerTitle
                Spacer(minLength: 16)
                weekNavigation
            }
            VStack(alignment: .leading, spacing: 10) {
                headerTitle
                weekNavigation
            }
        }
    }

    private var headerTitle: some View {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text("Weekly Report")
                } icon: {
                    Image(systemName: "chart.bar.fill").foregroundStyle(Palette.done)
                }
                .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("\(WeekRange.title(for: weekStart)) · \(WeekRange.rangeText(for: weekStart))")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
    }

    private var weekNavigation: some View {
            HStack(spacing: 4) {
                Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous week")
                Button("This Week") { withAnimation(AppStyle.spring) { weekStart = WeekRange.start(of: Date()) } }
                    .disabled(isCurrentWeek)
                Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next week")
                    .disabled(isCurrentWeek)
            }
            .buttonStyle(.bordered)
            .fixedSize()
    }

    private func stats(_ report: WeeklyReport) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { statTiles(report) }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                let tiles = statTileModels(report)
                GridRow { tiles[0]; tiles[1] }
                GridRow { tiles[2]; tiles[3] }
            }
        }
    }

    @ViewBuilder
    private func statTiles(_ report: WeeklyReport) -> some View {
        ForEach(Array(statTileModels(report).enumerated()), id: \.offset) { _, tile in tile }
    }

    private func statTileModels(_ report: WeeklyReport) -> [StatTile] {
        [
            StatTile(title: "Completed", value: "\(report.completed.count)", icon: "checkmark.circle.fill",
                     accent: Palette.done, footnote: deltaText(report.completedDelta),
                     footnoteTint: report.completedDelta >= 0 ? Palette.done : Palette.today),
            StatTile(title: "Created", value: "\(report.created.count)", icon: "plus.circle.fill",
                     accent: Palette.important, footnote: "new tasks added"),
            StatTile(title: "Due this week", value: rateText(report.completionRate), icon: "target",
                     accent: Palette.upcoming,
                     footnote: "\(report.dueThisWeek.filter(\.completed).count) of \(report.dueThisWeek.count) done",
                     progress: report.completionRate),
            StatTile(title: "Overdue", value: "\(report.overdue.count)", icon: "exclamationmark.circle.fill",
                     accent: Palette.today, footnote: report.overdue.isEmpty ? "all caught up" : "need attention"),
        ]
    }

    @ViewBuilder
    private func breakdowns(_ report: WeeklyReport) -> some View {
        BreakdownCard(title: "Completed by project", icon: "folder.fill", accent: Palette.project,
                      items: report.byProject, emptyText: "Nothing completed yet")
            .frame(minWidth: 260)
        BreakdownCard(title: "Completed by priority", icon: "flag.fill", accent: Palette.today,
                      items: report.byPriority, emptyText: "Nothing completed yet")
            .frame(minWidth: 260)
    }

    private func completedList(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(section: TaskListSection(id: "done", title: "Completed this week",
                                                       icon: "checkmark.circle.fill", accent: Palette.done,
                                                       tasks: report.completed))
            if report.completed.isEmpty {
                emptyLine("No tasks completed this week yet.")
            } else {
                ForEach(report.completedByDay(), id: \.day) { group in
                    Text(group.day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                    ForEach(group.tasks, id: \.id) { row(for: $0) }
                }
            }
        }
        .card(padding: 10)
    }

    private func taskCard(title: String, icon: String, accent: Color, tasks: [Task], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeaderView(section: TaskListSection(id: title, title: title, icon: icon, accent: accent, tasks: tasks))
                .padding(.bottom, 4)
            if tasks.isEmpty {
                emptyLine(emptyText)
            } else {
                ForEach(tasks, id: \.id) { row(for: $0) }
            }
        }
        .card(padding: 10)
    }

    private func row(for task: Task) -> some View {
        TaskRowView(
            task: task,
            isSelected: selectedTaskID == task.id,
            projects: store.projects,
            onToggle: { _Concurrency.Task { await store.toggle(task) } },
            onSelect: { withAnimation(AppStyle.spring) { selectedTaskID = task.id } },
            onUpdate: { patch in _Concurrency.Task { await store.update(task, patch) } },
            onDelete: { pendingDelete = task }
        )
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func shiftWeek(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: weekStart) else { return }
        withAnimation(AppStyle.spring) { weekStart = min(next, WeekRange.start(of: Date())) }
    }

    private func deltaText(_ delta: Int) -> String {
        switch delta {
        case 0: return "same as last week"
        case let d where d > 0: return "▲ \(d) vs last week"
        default: return "▼ \(-delta) vs last week"
        }
    }

    private func rateText(_ rate: Double?) -> String {
        rate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
    }
}

// MARK: - Cards

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color
    let footnote: String
    var footnoteTint: Color = .secondary
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if let progress {
                    ZStack {
                        Circle().stroke(accent.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 18, height: 18)
                    .animation(AppStyle.spring, value: progress)
                }
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(footnote)
                .font(.caption)
                .foregroundStyle(footnoteTint)
                .lineLimit(1)
        }
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

private struct ReportChartCard: View {
    let daily: [WeeklyReport.DayCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daily activity", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                legend("Completed", Palette.done)
                legend("Created", Palette.important)
            }
            Chart {
                ForEach(daily) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Tasks", day.completed))
                        .foregroundStyle(by: .value("Kind", "Completed"))
                        .position(by: .value("Kind", "Completed"))
                        .cornerRadius(4)
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Tasks", day.created))
                        .foregroundStyle(by: .value("Kind", "Created"))
                        .position(by: .value("Kind", "Created"))
                        .cornerRadius(4)
                }
            }
            .chartForegroundStyleScale(["Completed": Palette.done, "Created": Palette.important])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 170)
        }
        .card(padding: 14)
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct BreakdownCard: View {
    let title: String
    let icon: String
    let accent: Color
    let items: [WeeklyReport.Breakdown]
    let emptyText: String

    private var maxCount: Int { max(items.map(\.count).max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
            if items.allSatisfy({ $0.count == 0 }) {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 12, design: .rounded))
                            .lineLimit(1)
                            .frame(width: 90, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(accent.opacity(0.85))
                                .frame(width: max(4, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                        }
                        .frame(height: 8)
                        Text("\(item.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}
