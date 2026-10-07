import AppKit
import TrainCore

/// What the menu bar shows. Built by the conductor from engine state.
struct MenuSummary {
    var headline: String
    var carCount: Int?
    var best: Run?
    var carsToday: Int
    var derailsToday: Int
    var isPaused: Bool
    var showTrain: Bool
    var canCopy: Bool
}

/// The status item and its menu.
final class StatusMenu: NSObject, NSMenuDelegate {
    var onCopy: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onToggleShow: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var summary = MenuSummary(headline: "No train yet", carCount: nil, best: nil, carsToday: 0, derailsToday: 0, isPaused: false, showTrain: true, canCopy: false)

    override init() {
        super.init()
        menu.delegate = self
        item.menu = menu
        if let button = item.button {
            let image = NSImage(systemSymbolName: "train.side.front.car", accessibilityDescription: "Train of Thought")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        }
        render()
    }

    func update(_ summary: MenuSummary) {
        self.summary = summary
        render()
    }

    /// Briefly shows a symbol in place of the count: 💥 on a derail.
    func flash(_ text: String, for seconds: TimeInterval = 2.5) {
        item.button?.title = " " + text
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.render() }
    }

    private func render() {
        guard let button = item.button else { return }
        if summary.isPaused {
            button.title = ""
            button.appearsDisabled = true
        } else {
            button.appearsDisabled = false
            if let count = summary.carCount {
                button.title = " \(count)"
            } else {
                button.title = ""
            }
        }
        button.toolTip = summary.headline
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled(summary.headline))
        if let best = summary.best {
            menu.addItem(disabled("Best run: \(best.cars) cars · \(ShareText.format(best.duration)) in \(best.app.name)"))
        }
        if summary.carsToday > 0 || summary.derailsToday > 0 {
            let derails = summary.derailsToday == 1 ? "1 derailment" : "\(summary.derailsToday) derailments"
            menu.addItem(disabled("Today: \(summary.carsToday) cars · \(derails)"))
        }
        menu.addItem(.separator())

        let copy = NSMenuItem(title: "Copy Train", action: #selector(copyTrain), keyEquivalent: "c")
        copy.target = self
        copy.isEnabled = summary.canCopy
        menu.addItem(copy)

        let pause = NSMenuItem(title: summary.isPaused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)

        let show = NSMenuItem(title: "Show Train on Screen", action: #selector(toggleShow), keyEquivalent: "")
        show.target = self
        show.state = summary.showTrain ? .on : .off
        menu.addItem(show)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let github = NSMenuItem(title: "Train of Thought on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        github.target = self
        menu.addItem(github)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Train of Thought", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func copyTrain() { onCopy?() }
    @objc private func togglePause() { onTogglePause?() }
    @objc private func toggleShow() { onToggleShow?() }
    @objc private func openSettings() { onSettings?() }
    @objc private func quit() { onQuit?() }
    @objc private func openGitHub() {
        if let url = URL(string: ShareText.repoURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
