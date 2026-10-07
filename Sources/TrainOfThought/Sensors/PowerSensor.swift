import AppKit
import TrainCore

/// Sleep, wake, lock, unlock, screensaver, fast user switching. All of
/// these mean "you stepped away", which parks the train rather than
/// derailing it.
final class PowerSensor {
    var onAway: ((StationReason) -> Void)?
    var onBack: (() -> Void)?

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.onAway?(.sleep) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.onAway?(.sleep) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.onAway?(.screenLocked) }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.onBack?() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.onBack?() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.onBack?() }

        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.onAway?(.screenLocked) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.onBack?() }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { [weak self] in self?.onAway?(.screensaver) }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { [weak self] in self?.onBack?() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        tokens.append((center, token))
    }

    deinit {
        for (center, token) in tokens {
            center.removeObserver(token)
        }
    }
}
