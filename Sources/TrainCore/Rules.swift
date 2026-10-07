import Foundation

/// An application, identified the way macOS identifies it.
public struct App: Hashable, Codable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// The kinds of car that can couple onto a train. The order is the order
/// they appear in; see `Rules.car(at:)`.
public enum CarKind: String, Codable, CaseIterable {
    case boxcar
    case tanker
    case hopper
    case passenger
    case flatbed
}

public struct Car: Equatable, Codable {
    /// Zero-based position behind the locomotive.
    public let index: Int
    public let kind: CarKind
    /// Every `Rules.goldEvery`-th car is gold. With the default five-minute
    /// interval that is one gold car per half hour.
    public let isGold: Bool

    public init(index: Int, kind: CarKind, isGold: Bool) {
        self.index = index
        self.kind = kind
        self.isGold = isGold
    }
}

/// Why a train stopped at the station.
public enum StationReason: String, Codable {
    case idle
    case screenLocked
    case sleep
    case screensaver
}

/// Why a train derailed.
public enum DerailCause: Equatable, Codable {
    case switchedTo(App)
    case notification
}

/// The rules of the railway. Everything the user can tune lives here, and
/// the engine reads nothing else.
public struct Rules: Equatable {
    /// Seconds between cars. Default five minutes.
    public var carInterval: TimeInterval
    /// Seconds another app may be frontmost before the train derails.
    /// Coming back inside the grace is a near miss.
    public var grace: TimeInterval
    /// Whether a notification banner derails the train.
    public var derailOnNotification: Bool
    /// Bundle identifiers that never derail anything: launchers, password
    /// managers, system prompts. Built in; see `defaultPassengers`.
    public var passengers: Set<String>
    /// The user's ride-along apps. Switching to a crew app does not derail
    /// the train, and the train stays attributed to the app it left with.
    public var crew: Set<String>

    public static let goldEvery = 6

    public init(
        carInterval: TimeInterval = 5 * 60,
        grace: TimeInterval = 5,
        derailOnNotification: Bool = true,
        passengers: Set<String> = Rules.defaultPassengers,
        crew: Set<String> = []
    ) {
        self.carInterval = carInterval
        self.grace = grace
        self.derailOnNotification = derailOnNotification
        self.passengers = passengers
        self.crew = crew
    }

    public static let defaultPassengers: Set<String> = [
        // Launchers and command palettes.
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "com.alfredapp.Alfred",
        "com.apple.ScreenContinuity",
        // Password managers.
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        // The desktop and Finder are the hallway between rooms, not a room.
        "com.apple.finder",
        // System chrome and prompts.
        "com.apple.SecurityAgent",
        "com.apple.loginwindow",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.ScreenSaver.Engine",
        "com.apple.UserNotificationCenter",
        "com.apple.CoreServices.UIAgent",
        "com.apple.screencaptureui",
        "com.apple.screencapture",
        // Ourselves.
        "com.vsahasi.TrainOfThought",
    ]

    /// Passengers and crew alike: switching to one of these never derails.
    public func ridesAlong(_ bundleID: String) -> Bool {
        passengers.contains(bundleID) || crew.contains(bundleID)
    }

    /// The car that couples at a given zero-based position.
    public static func car(at index: Int) -> Car {
        let kinds = CarKind.allCases
        let kind = kinds[index % kinds.count]
        let isGold = (index + 1) % goldEvery == 0
        return Car(index: index, kind: kind, isGold: isGold)
    }
}
