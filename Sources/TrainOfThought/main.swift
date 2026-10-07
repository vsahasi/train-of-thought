import AppKit

// `--probe` prints NotificationCenter window changes so the banner sensor
// can be checked against a new macOS release without the UI.
if CommandLine.arguments.contains("--probe") {
    NotificationSensor.probe()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var conductor: Conductor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let conductor = Conductor()
        self.conductor = conductor
        conductor.start()
        if CommandLine.arguments.contains("--settings") {
            conductor.showSettings()
        } else {
            conductor.showWelcomeIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
