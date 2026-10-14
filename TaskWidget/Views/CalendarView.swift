import SwiftUI

/// Month calendar plus a detail panel listing every task on the selected day.
struct CalendarView: View {
    let store: TaskStore
    @Binding var selectedTaskID: Int?
    let search: String
    var quickAddFocus: FocusState<Bool>.Binding

    @State private var month = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var pendingDelete: Task?

    /// Side-by-side above this width, stacked below it.
    private let sideBySideWidth: CGFloat = 860

    private var visibleTasks: [Task] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? store.tasks : store.tasks.filter { $0.matches(query) }
    }

    private var dayTasks: [Task] {
        visibleTasks.filter { $0.planDay == selectedDay }
            .sorted { ($0.completed ? 1 : 0, -$0.priority.rank) < ($1.completed ? 1 : 0, -$1.priority.rank) }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if geo.size.width >= sideBySideWidth {
                        HStack(alignment: .top, spacing: 16) {
                            grid
                            dayPanel.frame(width: 300)
                        }
                    } else {
                        grid
                        dayPanel
                    }
                }
                .padding(24)
            }
        }
        .onChange(of: selectedDay) { _, day in
            // Picking a padded day from a neighbouring month moves the grid there.
            if !Calendar.current.isDate(day, equalTo: month, toGranularity: .month) {
                withAnimation(AppStyle.spring) { month = day }
            }
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

    // MARK: - Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                monthTitle
                Spacer(minLength: 16)
                monthNavigation
            }
            VStack(alignment: .leading, spacing: 10) {
                monthTitle
                monthNavigation
            }
        }
    }

    private var monthTitle: some View {
            Label {
                Text(month, format: .dateTime.month(.wide).year())
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "calendar").foregroundStyle(Palette.today)
            }
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .fixedSize()
    }

    private var monthNavigation: some View {
            HStack(spacing: 4) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous month")
                Button("Today") { jumpToToday() }
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next month")
            }
            .buttonStyle(.bordered)
            .fixedSize()
    }

    private var grid: some View {
        MonthGridView(
            month: month,
            tasks: visibleTasks,
            selectedDay: $selectedDay,
            onOpenTask: { task in
                selectedDay = task.planDay ?? selectedDay
                withAnimation(AppStyle.spring) { selectedTaskID = task.id }
            },
            onReschedule: { task, day in
                // Dragging moves the do date when the task has one, otherwise the due date.
                let date = TaskPatch.DueDate.set(TaskDate.string(from: day))
                let patch = task.scheduledDay != nil ? TaskPatch(scheduledDate: date) : TaskPatch(dueDate: date)
                _Concurrency.Task { await store.update(task, patch) }
            }
        )
        .card(padding: 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Selected day

    private var dayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay, format: .dateTime.weekday(.wide))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Calendar.current.isDateInToday(selectedDay) ? Palette.today : .secondary)
                HStack {
                    Text(selectedDay, format: .dateTime.month(.wide).day())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    CountBadge(count: dayTasks.filter { !$0.completed }.count, accent: Palette.today)
                }
            }
            QuickAddBar(defaults: QuickAddDefaults(project: nil, priority: .medium, due: nil, scheduled: selectedDay),
                        projects: store.projects, focus: quickAddFocus) { title, project, priority, due, scheduled in
                await store.create(title: title, project: project, priority: priority, due: due, scheduled: scheduled)
            }
            if dayTasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.upcoming.gradient)
                    Text("Nothing scheduled")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Add a task above or drag one onto this day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(dayTasks, id: \.id) { task in
                        TaskRowView(
                            task: task,
                            isSelected: selectedTaskID == task.id,
                            projects: store.projects,
                            onToggle: { _Concurrency.Task { await store.toggle(task) } },
                            onSelect: { withAnimation(AppStyle.spring) { selectedTaskID = task.id } },
                            onUpdate: { patch in _Concurrency.Task { await store.update(task, patch) } },
                            onDelete: { pendingDelete = task }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .card(padding: 6)
            }
        }
        .animation(AppStyle.spring, value: dayTasks.map(\.id))
    }

    // MARK: - Navigation

    private func shiftMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(AppStyle.spring) { month = next }
    }

    private func jumpToToday() {
        let today = Calendar.current.startOfDay(for: Date())
        withAnimation(AppStyle.spring) {
            month = today
            selectedDay = today
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}
