import AppKit
import TrainCore

/// Which app is frontmost. Wraps `NSWorkspace` activation notifications.
final class FocusSensor {
    var onActivate: ((App) -> Void)?
    private var token: NSObjectProtocol?

    init() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onActivate?(App(running))
        }
    }

    var frontmost: App? {
        NSWorkspace.shared.frontmostApplication.map(App.init)
    }

    deinit {
        if let token = token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
}

extension App {
    init(_ running: NSRunningApplication) {
        self.init(
            bundleID: running.bundleIdentifier ?? "pid.\(running.processIdentifier)",
            name: running.localizedName ?? "Unknown"
        )
    }
}
