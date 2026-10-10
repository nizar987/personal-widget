import SwiftUI

/// Breakpoints for the responsive detail area.
private enum DetailLayout {
    /// Below this detail width the editor opens as a sheet instead of a side panel.
    static let dockThreshold: CGFloat = 660

    static func panelWidth(for detailWidth: CGFloat) -> CGFloat {
        min(360, max(300, detailWidth * 0.36))
    }
}

struct ContentView: View {
    let store: TaskStore
    @State private var selection: SidebarItem? = .smart(.today)
    @State private var selectedTaskID: Int?
    @State private var search = ""
    @FocusState private var quickAddFocused: Bool

    private var currentItem: SidebarItem { selection ?? .smart(.today) }
    private var selectedTask: Task? { store.task(id: selectedTaskID) }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            GeometryReader { geo in
                detail(width: geo.size.width)
            }
            .navigationTitle(currentItem.title)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search tasks")
        .toolbar { toolbar }
        .task { await store.load() }
        .onChange(of: selection) { selectedTaskID = nil }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Responsive detail

    /// Wide: list + docked editor panel. Narrow: full-width list, editor in a sheet.
    private func detail(width: CGFloat) -> some View {
        let docked = width >= DetailLayout.dockThreshold
        return HStack(spacing: 0) {
            mainContent
                .frame(maxWidth: .infinity)
            if docked, let task = selectedTask {
                Divider()
                editor(for: task)
                    .frame(width: DetailLayout.panelWidth(for: width))
                    .background(Color.primary.opacity(0.025))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(AppStyle.spring, value: docked && selectedTask != nil)
        .sheet(isPresented: sheetBinding(docked: docked)) {
            if let task = selectedTask {
                editor(for: task)
                    .frame(width: 400, height: 600)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch currentItem {
        case .calendar:
            CalendarView(store: store, selectedTaskID: $selectedTaskID, search: search,
                         quickAddFocus: $quickAddFocused)
        case .report:
            WeeklyReportView(store: store, weekStart: reportWeekBinding, selectedTaskID: $selectedTaskID)
        case .smart, .project:
            TaskListView(item: currentItem, store: store, selectedTaskID: $selectedTaskID,
                         search: search, quickAddFocus: $quickAddFocused)
        }
    }

    /// Week navigation inside the report updates the sidebar selection.
    private var reportWeekBinding: Binding<Date> {
        Binding(
            get: {
                if case .report(let start) = currentItem { return start }
                return WeekRange.start(of: Date())
            },
            set: { selection = .report(weekStart: $0) }
        )
    }

    private func editor(for task: Task) -> some View {
        TaskEditorView(
            task: task,
            projects: store.projects,
            onSave: { patch in _Concurrency.Task { await store.update(task, patch) } },
            onToggle: { _Concurrency.Task { await store.toggle(task) } },
            onDelete: {
                selectedTaskID = nil
                _Concurrency.Task { await store.delete(task) }
            },
            onClose: { selectedTaskID = nil }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                _Concurrency.Task { await store.load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (⌘R)")

            Button {
                if selection == .smart(.completed) || !currentItem.isTaskList && currentItem != .calendar {
                    selection = .smart(.today)
                }
                quickAddFocused = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("New Task (⌘N)")
        }
    }

    // MARK: - Bindings

    private func sheetBinding(docked: Bool) -> Binding<Bool> {
        Binding(get: { !docked && selectedTask != nil }, set: { if !$0 && !docked { selectedTaskID = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil && !store.isOffline },
                set: { if !$0 { store.errorMessage = nil } })
    }
}
