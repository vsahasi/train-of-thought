import AppKit

/// A transparent, click-through strip along the bottom of the main screen,
/// sitting just above the Dock, on every Space, over full-screen apps.
final class OverlayWindow: NSPanel {
    let scene = TrainScene(frame: .zero)
    private var observer: NSObjectProtocol?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: TrainScene.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = scene
        fit()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.fit() }
    }

    /// Sizes the window to the bottom of the screen that has the menu bar,
    /// just above the Dock if the Dock is there.
    func fit(force: Bool = false) {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: TrainScene.height)
        guard force || frame != self.frame else { return }
        setFrame(frame, display: true)
        scene.frame = NSRect(origin: .zero, size: frame.size)
        scene.relayout()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
