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
    /// Same routes as `taskwidget://` URLs; `object` is the URL string. Handy for scripts and tests.
    static let linkRequest = Notification.Name("com.multiagent.taskwidget.link")
}

enum WindowID {
    static let main = "main"
}

/// Menu-bar only by default (`LSUIElement`); a Dock icon and ⌘Tab entry only while the main
/// window is open. Minimising keeps the icon so the window can be restored from the Dock.
@MainActor
enum DockPresence {
    static func mainWindowDidOpen() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func mainWindowDidClose() {
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }
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
    let noteStore = NoteStore()
    let router = AppRouter()
    /// Set in `applicationDidFinishLaunching`; ContentView reads it for the ⌘N toolbar button.
    private(set) var quickCaptureOpener: ((QuickCaptureMode) -> Void)?
    private(set) lazy var quickCapture = QuickCaptureController(store: store, noteStore: noteStore)
    private var refreshTimer: Timer?
    private static let refreshInterval: TimeInterval = 5 * 60

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be set before launch completes so "Understood" taps that launched the app arrive.
        DailyReminderScheduler.shared.configure()
        DailyReminderScheduler.shared.onOpenApp = { [weak self] in self?.showMainWindow() }
        store.onTasksChanged = { DailyReminderScheduler.shared.tasksChanged($0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launching (e.g. at login) pulls fresh data into the desktop widget.
        WidgetCenter.shared.reloadAllTimelines()
        quickCaptureOpener = { [weak self] mode in self?.quickCapture.show(mode: mode) }
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
        DistributedNotificationCenter.default().addObserver(
            forName: .linkRequest, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.object as? String
            MainActor.assumeIsolated {
                if let raw, let url = URL(string: raw) { self?.application(NSApp, open: [url]) }
            }
        }
        _Concurrency.Task { await store.load() }
        // Independent of loading: the permission prompt may sit unanswered.
        _Concurrency.Task {
            await DailyReminderScheduler.shared.requestAuthorization()
            DailyReminderScheduler.shared.settingsChanged()
        }
        startBackgroundRefresh()
    }

    /// Keeps tasks (and therefore reminder text) current even when changes come from the widget
    /// or another client, and after the Mac wakes up.
    private func startBackgroundRefresh() {
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInBackground() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInBackground() }
        }
    }

    private func refreshInBackground() {
        _Concurrency.Task { await store.load() }
    }

    /// `taskwidget://` links from the widget.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let link = AppLink(url: url) else {
                quickCaptureLog.error("ignored unknown link \(url.absoluteString, privacy: .public)")
                continue
            }
            quickCaptureLog.info("open link \(url.absoluteString, privacy: .public)")
            switch link {
            case .quickCapture:
                quickCapture.show()
            case .open:
                showMainWindow()
            case .task(let id):
                router.requestedTaskID = id
                showMainWindow()
            }
        }
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
