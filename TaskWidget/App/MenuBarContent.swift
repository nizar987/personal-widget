import SwiftUI
import KeyboardShortcuts

/// Status-bar icon. Also hands SwiftUI's `openWindow` to AppKit so reopen events can use it.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "checklist")
            .onAppear {
                WindowOpener.openMain = { openWindow(id: WindowID.main) }
            }
    }
}

/// Dropdown menu: quick capture, today's tasks, window, settings, quit.
struct MenuBarContent: View {
    let store: TaskStore
    let onQuickCapture: () -> Void

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var todayTasks: [Task] {
        SidebarItem.smart(.today).matching(store.tasks, now: Date()).sorted(by: TaskSort.byDateThenPriority)
    }

    private var shortcutText: String {
        KeyboardShortcuts.getShortcut(for: .quickCapture).map { "\($0)" } ?? "no shortcut"
    }

    var body: some View {
        Button("New Task…   \(shortcutText)", action: onQuickCapture)
        Button("Open TaskWidget", action: openMain)
            .keyboardShortcut("o")
        Divider()
        Section(todayTasks.isEmpty ? "Today · all clear" : "Today · \(todayTasks.count) open") {
            ForEach(todayTasks.prefix(6), id: \.id) { task in
                Button {
                    _Concurrency.Task { await store.toggle(task) }
                } label: {
                    Label(menuTitle(task), systemImage: "circle")
                }
            }
            if todayTasks.count > 6 {
                Button("+\(todayTasks.count - 6) more…", action: openMain)
            }
        }
        Divider()
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit TaskWidget") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openMain() {
        WindowOpener.openMain = { openWindow(id: WindowID.main) }
        NSApp.activate()
        openWindow(id: WindowID.main)
    }

    private func menuTitle(_ task: Task) -> String {
        let title = task.title.count > 40 ? String(task.title.prefix(39)) + "…" : task.title
        return task.isOverdue() ? "\(title)  · overdue" : title
    }
}
