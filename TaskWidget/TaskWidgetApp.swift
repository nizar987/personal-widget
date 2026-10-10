import SwiftUI

/// Menu-bar app: ⌥Space opens quick capture, the menu opens the main window. The Dock icon only
/// appears while that window is open (see `DockPresence`).
@main
struct TaskWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("TaskWidget", id: WindowID.main) {
            ContentView(store: appDelegate.store)
                .frame(minWidth: 640, minHeight: 460)
                .onAppear { DockPresence.mainWindowDidOpen() }
                .onDisappear { DockPresence.mainWindowDidClose() }
        }
        .defaultSize(width: 1100, height: 700)
        .windowToolbarStyle(.unified)
        // Launch (and login) quietly into the menu bar instead of popping a window.
        .defaultLaunchBehavior(.suppressed)
        .commands {
            // ⌘N creates a task (toolbar button) instead of opening another window.
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContent(store: appDelegate.store,
                           onQuickCapture: { appDelegate.quickCapture.show() })
        } label: {
            MenuBarLabel()
        }

        Settings {
            SettingsView()
        }
    }
}
