import AppKit
import KeyboardShortcuts
import OSLog
import WidgetKit

let quickCaptureLog = Logger(subsystem: "com.multiagent.taskwidget", category: "quickCapture")

extension KeyboardShortcuts.Name {
    /// Global quick-capture hotkey. Default ⌥Space; changeable in Settings.
    static let quickCapture = Self("quickCapture", initial: .init(.space, modifiers: [.option]))
}

extension Notification.Name {
    /// Post from anywhere (Shortcuts, scripts) to open quick capture:
    /// `DistributedNotificationCenter.default().post(name: .init("com.multiagent.taskwidget.quickCapture"), object: nil)`
    static let quickCaptureRequest = Notification.Name("com.multiagent.taskwidget.quickCapture")
}

enum WindowID {
    static let main = "main"
}

/// Lets AppKit code open SwiftUI windows (set by the menu bar label once SwiftUI is up).
@MainActor
enum WindowOpener {
    static var openMain: (() -> Void)?
}

/// Menu-bar app lifecycle: shared store, global hotkey, quick-capture panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TaskStore()
    private(set) lazy var quickCapture = QuickCaptureController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launching (e.g. at login) pulls fresh data into the desktop widget.
        WidgetCenter.shared.reloadAllTimelines()
        let shortcut = KeyboardShortcuts.getShortcut(for: .quickCapture).map { "\($0)" } ?? "none"
        quickCaptureLog.info("registering quick capture hotkey: \(shortcut, privacy: .public)")
        KeyboardShortcuts.onKeyUp(for: .quickCapture) { [weak self] in
            quickCaptureLog.info("hotkey pressed")
            self?.quickCapture.toggle()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .quickCaptureRequest, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                quickCaptureLog.info("quick capture requested via notification")
                self?.quickCapture.show()
            }
        }
        _Concurrency.Task { await store.load() }
    }

    /// Closing the window keeps the app alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again from Finder/Spotlight shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    func showMainWindow() {
        NSApp.activate()
        WindowOpener.openMain?()
    }
}
