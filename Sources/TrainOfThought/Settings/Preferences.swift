import Combine
import Foundation
import ServiceManagement
import TrainCore

enum TrainSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var scale: CGFloat {
        switch self {
        case .small: return 2
        case .medium: return 3
        case .large: return 4
        }
    }
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

/// User settings, backed by `UserDefaults`. Publishes changes so the
/// conductor can hand new rules to the engine and the settings window
/// stays live.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var carIntervalMinutes: Int { didSet { defaults.set(carIntervalMinutes, forKey: Key.carInterval) } }
    @Published var graceSeconds: Int { didSet { defaults.set(graceSeconds, forKey: Key.grace) } }
    @Published var derailOnNotification: Bool { didSet { defaults.set(derailOnNotification, forKey: Key.notifications) } }
    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: Key.idle) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
    @Published var showTrain: Bool { didSet { defaults.set(showTrain, forKey: Key.showTrain) } }
    @Published var chugging: Bool { didSet { defaults.set(chugging, forKey: Key.chugging) } }
    @Published var trainSize: TrainSize { didSet { defaults.set(trainSize.rawValue, forKey: Key.size) } }
    @Published var fadeWhenQuiet: Bool { didSet { defaults.set(fadeWhenQuiet, forKey: Key.fade) } }
    @Published var crew: [String] { didSet { defaults.set(crew, forKey: Key.crew) } }
    @Published var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: Key.welcome) } }

    private let defaults: UserDefaults

    private enum Key {
        static let carInterval = "carIntervalMinutes"
        static let grace = "graceSeconds"
        static let notifications = "derailOnNotification"
        static let idle = "idleMinutes"
        static let sound = "soundEnabled"
        static let showTrain = "showTrain"
        static let chugging = "chugging"
        static let size = "trainSize"
        static let fade = "fadeWhenQuiet"
        static let crew = "crew"
        static let welcome = "hasSeenWelcome"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.carInterval: 5,
            Key.grace: 5,
            Key.notifications: true,
            Key.idle: 10,
            Key.sound: false,
            Key.showTrain: true,
            Key.chugging: false,
            Key.size: TrainSize.small.rawValue,
            Key.fade: true,
            Key.crew: [String](),
            Key.welcome: false,
        ])
        carIntervalMinutes = defaults.integer(forKey: Key.carInterval)
        graceSeconds = defaults.integer(forKey: Key.grace)
        derailOnNotification = defaults.bool(forKey: Key.notifications)
        idleMinutes = defaults.integer(forKey: Key.idle)
        soundEnabled = defaults.bool(forKey: Key.sound)
        showTrain = defaults.bool(forKey: Key.showTrain)
        chugging = defaults.bool(forKey: Key.chugging)
        trainSize = TrainSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .small
        fadeWhenQuiet = defaults.bool(forKey: Key.fade)
        crew = defaults.stringArray(forKey: Key.crew) ?? []
        hasSeenWelcome = defaults.bool(forKey: Key.welcome)
    }

    /// `TRAIN_CAR_SECONDS=3 open build/Train\ of\ Thought.app` speeds up the
    /// clock for development. Minutes per car is used otherwise.
    var carInterval: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["TRAIN_CAR_SECONDS"], let seconds = TimeInterval(raw), seconds > 0 {
            return seconds
        }
        return TimeInterval(carIntervalMinutes * 60)
    }

    var rules: Rules {
        Rules(
            carInterval: carInterval,
            grace: TimeInterval(graceSeconds),
            derailOnNotification: derailOnNotification,
            crew: Set(crew)
        )
    }

    // MARK: Launch at login

    /// Only works from inside a real `.app` bundle; from `swift run` the
    /// toggle shows as off and setting it fails quietly.
    var launchesAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Launch at login: \(error.localizedDescription)")
                }
                objectWillChange.send()
            }
        }
    }
}
