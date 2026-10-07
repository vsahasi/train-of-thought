import AppKit
import SwiftUI

/// Shown once, on first launch. Three rules and a button.
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show(onSettings: @escaping () -> Void) {
        let view = WelcomeView(
            onStart: { Self.window?.close() },
            onSettings: { Self.window?.close(); onSettings() }
        )
        let hosting = NSHostingController(rootView: view)
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Train of Thought"
        panel.styleMask = [.titled, .closable]
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let onStart: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSImage(cgImage: Pixel.image(Sprite.locomotive), size: Pixel.size(of: Sprite.locomotive)))
                .interpolation(.none)
                .frame(height: Pixel.size(of: Sprite.locomotive).height)

            Text("All aboard.")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 10) {
                rule("A tiny train now runs along the bottom of your screen while you stay in one app.")
                rule("Every five minutes it gains a car.")
                rule("Switch apps or get a notification and it derails. Lock your screen or step away and it just waits at the station.")
            }

            Text("Look for the train in the menu bar. There are no permissions to grant and nothing leaves this Mac.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Settings…", action: onSettings)
                Spacer()
                Button("Let's go", action: onStart)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440)
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("•").foregroundColor(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
