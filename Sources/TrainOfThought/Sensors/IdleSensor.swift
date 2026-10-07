import CoreGraphics
import Foundation

/// Seconds since the last keyboard or mouse input, via Quartz Event
/// Services. No permission needed; it reads a single number, not events.
final class IdleSensor {
    var onIdle: (() -> Void)?
    var onActive: (() -> Void)?
    var threshold: TimeInterval = 10 * 60
    private(set) var isIdle = false

    private static let inputs: [CGEventType] = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .scrollWheel, .keyDown, .flagsChanged,
    ]

    static var secondsSinceLastInput: TimeInterval {
        inputs
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    /// Call once a second.
    func check() {
        let idle = Self.secondsSinceLastInput >= threshold
        guard idle != isIdle else { return }
        isIdle = idle
        if idle {
            onIdle?()
        } else {
            onActive?()
        }
    }
}
