import AppKit
import SwiftUI

/// Borderless, non-activating floating panel (Spotlight-style). It takes keyboard focus without
/// pulling the rest of the app forward, so closing it returns you to whatever you were doing.
final class QuickCapturePanel: NSPanel {
    var onResignKey: (() -> Void)?

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

        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        contentViewController = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
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
    private let session = QuickCaptureSession()
    private lazy var panel: QuickCapturePanel = makePanel()

    init(store: TaskStore) {
        self.store = store
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        session.prepare(projects: store.projects)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        // Refresh projects for `#` completion and the default project in the background.
        _Concurrency.Task {
            await store.load()
            session.updateProjects(store.projects)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func makePanel() -> QuickCapturePanel {
        let view = QuickCaptureView(session: session) { [weak self] draft, keepOpen in
            await self?.save(draft, keepOpen: keepOpen) ?? false
        } onClose: { [weak self] in
            self?.hide()
        }
        let panel = QuickCapturePanel(rootView: view)
        panel.onResignKey = { [weak self] in self?.hide() }
        return panel
    }

    private func save(_ draft: QuickCaptureDraft, keepOpen: Bool) async -> Bool {
        let project = draft.project ?? session.defaultProject
        let ok = await store.create(title: draft.title, project: project,
                                    priority: draft.priority ?? .medium, due: draft.due)
        guard ok else {
            session.errorMessage = store.errorMessage ?? "Couldn't save the task."
            return false
        }
        if draft.project != nil { session.rememberProject(project) }
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
