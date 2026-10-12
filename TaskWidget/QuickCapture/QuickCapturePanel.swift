import AppKit
import SwiftUI

/// Borderless, non-activating floating panel (Spotlight-style). It takes keyboard focus without
/// pulling the rest of the app forward, so closing it returns you to whatever you were doing.
final class QuickCapturePanel: NSPanel {
    var onResignKey: (() -> Void)?
    var onCancel: (() -> Void)?

    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: QuickCaptureLayout.width, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow

        // Sized manually (see `fit(to:)`): automatic hosting sizing fed back into layout and
        // either left the panel at 0×0 or recursed until the stack overflowed.
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = hosting
    }

    /// Measures the SwiftUI content; used before showing so the panel never opens at 0×0.
    func fitToContent() {
        guard let size = contentView?.fittingSize else { return }
        fit(to: size)
    }

    /// Resizes to `size`, keeping the top edge fixed so the text field doesn't jump.
    func fit(to size: CGSize) {
        guard size.width > 0, size.height > 0,
              abs(size.width - frame.width) > 0.5 || abs(size.height - frame.height) > 0.5 else { return }
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { orderOut(nil) }
    }
}

enum QuickCaptureLayout {
    static let width: CGFloat = 640
    /// Panel top sits this far down from the top of the visible screen area.
    static let topOffsetRatio: CGFloat = 0.22
}

/// Owns the panel, shows it on the screen under the mouse, and hides it when focus leaves.
@MainActor
final class QuickCaptureController {
    private let store: TaskStore
    private let noteStore: NoteStore
    private let session = QuickCaptureSession()
    private lazy var panel: QuickCapturePanel = makePanel()
    private var keyMonitor: Any?

    init(store: TaskStore, noteStore: NoteStore) {
        self.store = store
        self.noteStore = noteStore
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show(mode: QuickCaptureMode? = nil) {
        session.prepare(tasks: store.tasks, projects: store.projects, mode: mode)
        panel.fitToContent()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        quickCaptureLog.info("panel shown frame=\(NSStringFromRect(self.panel.frame), privacy: .public) key=\(self.panel.isKeyWindow)")
        // Refresh projects for `#` completion and the default project in the background.
        _Concurrency.Task {
            await store.load()
            session.update(tasks: store.tasks, projects: store.projects)
        }
    }

    func hide() {
        quickCaptureLog.info("panel hidden")
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    /// Tab / ↑ / ↓ / ↵ / Esc drive autocomplete. They're intercepted before the text field's
    /// editor sees them, and only while suggestions are visible.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel,
                  let key = QuickCaptureSession.Key(keyCode: event.keyCode),
                  event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) || key != .returnKey
            else { return event }
            return self.session.handle(key) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func makePanel() -> QuickCapturePanel {
        let view = QuickCaptureView(session: session) { [weak self] draft, mode, keepOpen in
            await self?.save(draft, mode: mode, keepOpen: keepOpen) ?? false
        } onClose: { [weak self] in
            self?.hide()
        } onSizeChange: { [weak self] size in
            self?.panel.fit(to: size)
        }
        let panel = QuickCapturePanel(rootView: view)
        panel.onResignKey = { [weak self] in self?.hide() }
        panel.onCancel = { [weak self] in self?.hide() }
        return panel
    }

    private func save(_ draft: QuickCaptureDraft, mode: QuickCaptureMode, keepOpen: Bool) async -> Bool {
        let ok: Bool
        if mode == .note {
            ok = await noteStore.create(content: draft.title)
            if !ok { session.errorMessage = noteStore.errorMessage ?? "Couldn't save the note." }
        } else {
            let project = draft.project ?? session.defaultProject
            ok = await store.create(title: draft.title, project: project,
                                    priority: draft.priority ?? .medium, due: draft.due)
            if !ok { session.errorMessage = store.errorMessage ?? "Couldn't save the task." }
        }
        guard ok else { return false }
        if mode == .task, let project = draft.project { session.rememberProject(project) }
        if !keepOpen {
            try? await _Concurrency.Task.sleep(for: .milliseconds(350))
            hide()
        }
        return true
    }

    /// Centered horizontally, in the upper part of the screen that holds the mouse pointer.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let top = visible.maxY - visible.height * QuickCaptureLayout.topOffsetRatio
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
    }
}
