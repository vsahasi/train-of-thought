import AppKit
import Combine
import TrainCore

/// Wires the sensors to the engine and the engine's effects to the screen,
/// the menu bar, the logbook and the speaker. The only place where time
/// is read.
final class Conductor {
    private var engine: Engine
    private var stats: Stats
    private let store: StatsStore
    private let prefs: Preferences

    private let overlay = OverlayWindow()
    private let menu = StatusMenu()
    private let settings = SettingsWindowController()
    private let toot = Toot()

    private let focus = FocusSensor()
    private let notifications = NotificationSensor()
    private let idle = IdleSensor()
    private let power = PowerSensor()

    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    /// What the overlay is showing, for the headline.
    private var braking: App?
    private var parkedReason: StationReason?
    /// A train that should roll in once the wreck animation finishes.
    private var arrivalAfterWreck: [Car]?

    init(prefs: Preferences = .shared, store: StatsStore = StatsStore(url: StatsStore.defaultURL())) {
        self.prefs = prefs
        self.store = store
        self.stats = store.load()
        self.engine = Engine(rules: prefs.rules)
        wire()
    }

    func start() {
        if let app = focus.frontmost {
            send(.appActivated(app, at: Date()))
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        applyPreferences()
        if prefs.showTrain {
            overlay.orderFrontRegardless()
        }
        refreshMenu()
    }

    // MARK: Wiring

    private func wire() {
        focus.onActivate = { [weak self] app in self?.send(.appActivated(app, at: Date())) }
        notifications.onBanner = { [weak self] in self?.send(.notification(at: Date())) }
        idle.onIdle = { [weak self] in self?.send(.stationArrive(.idle, at: Date())) }
        idle.onActive = { [weak self] in self?.send(.stationDepart(at: Date())) }
        power.onAway = { [weak self] reason in self?.send(.stationArrive(reason, at: Date())) }
        power.onBack = { [weak self] in self?.send(.stationDepart(at: Date())) }

        menu.onCopy = { [weak self] in self?.copyTrain() }
        menu.onTogglePause = { [weak self] in self?.togglePause() }
        menu.onToggleShow = { [weak self] in self?.prefs.showTrain.toggle() }
        menu.onSettings = { [weak self] in
            guard let self = self else { return }
            self.settings.show(prefs: self.prefs, stats: { self.stats })
        }
        menu.onQuit = { NSApp.terminate(nil) }

        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the value lands.
                DispatchQueue.main.async { self?.applyPreferences() }
            }
            .store(in: &subscriptions)
    }

    private func applyPreferences() {
        engine.rules = prefs.rules
        idle.threshold = TimeInterval(prefs.idleMinutes * 60)
        if Pixel.scale != prefs.trainSize.scale {
            Pixel.scale = prefs.trainSize.scale
            overlay.fit(force: true)
            overlay.scene.rebuild(cars: engine.session?.cars ?? [])
        }
        overlay.scene.fadesWhenQuiet = prefs.fadeWhenQuiet
        updateChugging()
        if prefs.derailOnNotification {
            notifications.start()
        } else {
            notifications.stop()
        }
        if prefs.showTrain && !engine.isPaused {
            if !overlay.isVisible {
                overlay.orderFrontRegardless()
                overlay.scene.rebuild(cars: engine.session?.cars ?? [])
            }
        } else {
            overlay.orderOut(nil)
        }
        refreshMenu()
    }

    private func tick() {
        let now = Date()
        send(.tick(at: now))
        idle.check()
        // The headline carries a live duration.
        if engine.session != nil {
            refreshMenu()
        }
    }

    // MARK: Engine

    private func send(_ event: Event) {
        let effects = engine.handle(event)
        for effect in effects {
            apply(effect)
        }
        if !effects.isEmpty {
            refreshMenu()
            updateChugging()
        }
    }

    private func updateChugging() {
        let scene = overlay.scene
        let shouldChug = prefs.chugging && prefs.showTrain && engine.session != nil && scene.isMoving && !scene.isBusy && !engine.isPaused
        if shouldChug {
            toot.startChugging()
        } else {
            toot.stopChugging()
        }
    }

    private func apply(_ effect: Effect) {
        let scene = overlay.scene
        if case .parked = effect {} else if case .paused = effect {} else {
            scene.noteActivity()
        }
        switch effect {
        case .sessionStarted:
            braking = nil
            parkedReason = nil
            if scene.isBusy {
                arrivalAfterWreck = []
            } else {
                scene.arrive(cars: [])
            }

        case .carAdded(let car, let total):
            scene.couple(car)
            if prefs.soundEnabled {
                toot.play(car.isGold || total % 12 == 0 ? .whistle : .couple)
            }

        case .derailed(let wreck):
            braking = nil
            record(wreck.run)
            if prefs.soundEnabled {
                toot.play(.derail)
            }
            menu.flash("💥")
            scene.derail { [weak self] in
                guard let self = self else { return }
                if let cars = self.arrivalAfterWreck {
                    self.arrivalAfterWreck = nil
                    scene.arrive(cars: cars)
                    self.updateChugging()
                }
            }

        case .rerouted:
            braking = nil
            scene.reroute { [weak self] in
                guard let self = self else { return }
                if let cars = self.arrivalAfterWreck {
                    self.arrivalAfterWreck = nil
                    scene.arrive(cars: cars)
                    self.updateChugging()
                }
            }

        case .nearMiss:
            braking = nil
            scene.nearMiss()
            if prefs.soundEnabled {
                toot.play(.nearMiss)
            }

        case .braking(let toward):
            braking = toward
            scene.setMoving(false)

        case .brakesReleased:
            braking = nil
            scene.setMoving(true)

        case .parked(let reason):
            braking = nil
            parkedReason = reason
            scene.setMoving(false)

        case .departed:
            parkedReason = nil
            scene.setMoving(true)

        case .retired(let run):
            parkedReason = nil
            record(run)
            scene.clear()

        case .paused(let run):
            if let run = run {
                record(run)
            }
            braking = nil
            parkedReason = nil
            scene.clear()
            overlay.orderOut(nil)

        case .resumed:
            if prefs.showTrain {
                overlay.orderFrontRegardless()
            }
        }
    }

    private func record(_ run: Run) {
        stats.record(run)
        do {
            try store.save(stats)
        } catch {
            NSLog("Could not save stats: \(error.localizedDescription)")
        }
    }

    // MARK: Menu

    private func refreshMenu() {
        let now = Date()
        let session = engine.session
        let headline: String
        if engine.isPaused {
            headline = "Paused"
        } else if let reason = parkedReason, let session = session {
            headline = "At the station (\(describe(reason))) · \(session.carCount) cars in \(session.app.name)"
        } else if let toward = braking, let session = session {
            headline = "Braking: \(toward.name) is in front · \(session.carCount) cars in \(session.app.name)"
        } else if let session = session {
            let cars = session.carCount == 1 ? "1 car" : "\(session.carCount) cars"
            headline = "\(cars) · \(ShareText.format(session.duration(at: now))) in \(session.app.name)"
        } else {
            headline = "No train yet"
        }
        let today = stats.recentRuns.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: now) }
        let derailsToday = today.filter { if case .derailed = $0.ending { return true } else { return false } }.count
        menu.update(MenuSummary(
            headline: headline,
            carCount: engine.isPaused ? nil : session?.carCount,
            best: stats.bestRun,
            carsToday: stats.carsToday(now: now) + (session?.carCount ?? 0),
            derailsToday: derailsToday,
            isPaused: engine.isPaused,
            showTrain: prefs.showTrain,
            canCopy: session != nil
        ))
    }

    private func describe(_ reason: StationReason) -> String {
        switch reason {
        case .idle: return "idle"
        case .screenLocked: return "screen locked"
        case .sleep: return "asleep"
        case .screensaver: return "screensaver"
        }
    }

    // MARK: Actions

    private func copyTrain() {
        guard let session = engine.session else { return }
        let text = ShareText.train(cars: session.carCount, duration: session.duration(at: Date()), appName: session.app.name)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        menu.flash("copied", for: 1.5)
    }

    private func togglePause() {
        if engine.isPaused {
            send(.resume(at: Date()))
        } else {
            send(.pause(at: Date()))
        }
    }

    func showSettings() {
        settings.show(prefs: prefs, stats: { [weak self] in self?.stats ?? Stats() })
    }

    func showWelcomeIfNeeded() {
        guard !prefs.hasSeenWelcome else { return }
        prefs.hasSeenWelcome = true
        WelcomeWindow.show { [weak self] in
            guard let self = self else { return }
            self.settings.show(prefs: self.prefs, stats: { self.stats })
        }
    }
}
