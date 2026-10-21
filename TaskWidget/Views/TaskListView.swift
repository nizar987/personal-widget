import SwiftUI

struct TaskListView: View {
    let item: SidebarItem
    let store: TaskStore
    @Binding var selectedTaskID: Int?
    let search: String
    var quickAddFocus: FocusState<Bool>.Binding

    @State private var pendingDelete: Task?
    @State private var confirmClearCompleted = false

    private var sections: [TaskListSection] {
        item.sections(from: store.tasks, search: search, now: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.isOffline { offlineBanner }
                if item != .smart(.completed) {
                    let defaults = item.quickAddDefaults()
                    QuickAddBar(defaults: defaults, projects: store.projects,
                                focus: quickAddFocus) { title, project, priority, due, scheduled in
                        await store.create(title: title, project: project, priority: priority,
                                           due: due, scheduled: scheduled, status: defaults.status)
                    }
                }
                if sections.isEmpty {
                    emptyState
                } else {
                    ForEach(sections) { section in
                        sectionCard(section)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(AppStyle.spring, value: sections.map(\.id))
        }
        .confirmationDialog("Delete “\(pendingDelete?.title ?? "")”?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let task = pendingDelete { delete(task) }
            }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Delete all completed tasks?", isPresented: $confirmClearCompleted, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                selectedTaskID = nil
                _Concurrency.Task { await store.deleteCompleted() }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.icon).foregroundStyle(item.accent)
                }
                .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if item == .smart(.completed) && !sections.isEmpty {
                Button("Clear All", role: .destructive) { confirmClearCompleted = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var subtitle: String {
        let count = sections.reduce(0) { $0 + $1.tasks.filter { !$0.completed || item == .smart(.completed) }.count }
        let date = Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        return "\(date) · \(count) \(count == 1 ? "task" : "tasks")"
    }

    private func sectionCard(_ section: TaskListSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeaderView(section: section)
                .padding(.bottom, 4)
            ForEach(section.tasks, id: \.id) { task in
                TaskRowView(
                    task: task,
                    isSelected: selectedTaskID == task.id,
                    projects: store.projects,
                    onToggle: { _Concurrency.Task { await store.toggle(task) } },
                    onSelect: { withAnimation(AppStyle.spring) { selectedTaskID = task.id } },
                    onUpdate: { patch in _Concurrency.Task { await store.update(task, patch) } },
                    onDelete: { pendingDelete = task }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .card(padding: 10)
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").foregroundStyle(Palette.upcoming)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't reach the backend").font(.system(size: 13, weight: .semibold))
                Text("Start the TaskWidget server (\(Constants.apiHostLabel)) — see backend/README.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { _Concurrency.Task { await store.load() } }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: search.isEmpty ? "checkmark.seal.fill" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(item.accent.gradient)
                .symbolEffect(.bounce, value: item)
            Text(search.isEmpty ? "All clear" : "No results for “\(search)”")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(search.isEmpty ? "Nothing in \(item.title) right now." : "Try a different search.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Delete

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func delete(_ task: Task) {
        if selectedTaskID == task.id { selectedTaskID = nil }
        pendingDelete = nil
        _Concurrency.Task { await store.delete(task) }
    }
}
