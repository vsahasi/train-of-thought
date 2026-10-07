import Foundation

/// A train in progress.
public struct Session: Equatable, Codable {
    public var app: App
    public var startedAt: Date
    public var lastCarAt: Date
    public var cars: [Car]

    public init(app: App, startedAt: Date) {
        self.app = app
        self.startedAt = startedAt
        self.lastCarAt = startedAt
        self.cars = []
    }

    public var carCount: Int { cars.count }

    public func duration(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }
}

/// A finished train. This is what gets remembered.
public struct Run: Equatable, Codable {
    public enum Ending: Equatable, Codable {
        case derailed(DerailCause)
        /// Retired quietly at the station because you came back to a
        /// different app.
        case retired(StationReason)
        case paused
    }

    public let app: App
    public let cars: Int
    public let startedAt: Date
    public let endedAt: Date
    public let ending: Ending

    public init(app: App, cars: Int, startedAt: Date, endedAt: Date, ending: Ending) {
        self.app = app
        self.cars = cars
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.ending = ending
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

public struct Wreck: Equatable {
    public let run: Run
    public let cause: DerailCause
}

/// Another app is frontmost; the train derails at `due` unless you return.
public struct PendingDerail: Equatable {
    public var toward: App
    public let due: Date
}

public enum Event: Equatable {
    case appActivated(App, at: Date)
    case notification(at: Date)
    case tick(at: Date)
    case pause(at: Date)
    case resume(at: Date)
    case stationArrive(StationReason, at: Date)
    case stationDepart(at: Date)
}

public enum Effect: Equatable {
    case sessionStarted(App)
    case carAdded(Car, total: Int)
    /// A train with cars came off the rails. Always followed by
    /// `sessionStarted` when a new train can leave.
    case derailed(Wreck)
    /// A lone locomotive (no cars yet) was switched away from. Nothing to
    /// lose, so no wreck and nothing recorded: the locomotive simply moves
    /// to the new line. Followed by `sessionStarted`.
    case rerouted(from: App)
    /// You switched away and came back inside the grace period.
    case nearMiss
    /// Another app is frontmost and the grace clock is running.
    case braking(toward: App)
    case brakesReleased
    /// The train stopped at the station and is waiting, cars intact.
    case parked(StationReason)
    /// You came back to the same app; the train leaves the station.
    case departed
    /// You came back to a different app; the old train is remembered and
    /// a new one leaves. Always followed by `sessionStarted`.
    case retired(Run)
    case paused(Run?)
    case resumed
}

public enum EngineState: Equatable {
    case idle
    case running(Session, pending: PendingDerail?)
    case parked(Session, StationReason)
    case paused
}

/// The state machine. Events in, effects out, no clock, no AppKit.
///
/// The app feeds it a `tick` once a second plus whatever the sensors see.
/// Everything that happens on screen is a reaction to the effects it
/// returns, which is what makes the rules testable in isolation.
public struct Engine {
    public private(set) var state: EngineState = .idle
    /// The frontmost app as last reported, tracked in every state so the
    /// engine knows where a new train should leave from.
    public private(set) var frontmost: App?
    public var rules: Rules

    public init(rules: Rules = Rules()) {
        self.rules = rules
    }

    public var session: Session? {
        switch state {
        case .running(let s, _), .parked(let s, _): return s
        case .idle, .paused: return nil
        }
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .appActivated(let app, let now): return activated(app, at: now)
        case .notification(let now): return notified(at: now)
        case .tick(let now): return tick(at: now)
        case .pause(let now): return pause(at: now)
        case .resume(let now): return resume(at: now)
        case .stationArrive(let reason, let now): return arrive(reason, at: now)
        case .stationDepart(let now): return depart(at: now)
        }
    }

    // MARK: - Transitions

    private mutating func activated(_ app: App, at now: Date) -> [Effect] {
        frontmost = app
        switch state {
        case .idle:
            return startIfPossible(at: now)

        case .running(let session, let pending):
            if app.bundleID == session.app.bundleID {
                guard pending != nil else { return [] }
                state = .running(session, pending: nil)
                return [.brakesReleased, .nearMiss]
            }
            if rules.ridesAlong(app.bundleID) {
                return []
            }
            if var pending = pending {
                pending.toward = app
                state = .running(session, pending: pending)
                return []
            }
            if rules.grace <= 0 {
                return derail(session, cause: .switchedTo(app), at: now)
            }
            state = .running(session, pending: PendingDerail(toward: app, due: now.addingTimeInterval(rules.grace)))
            return [.braking(toward: app)]

        case .parked, .paused:
            return []
        }
    }

    private mutating func notified(at now: Date) -> [Effect] {
        guard rules.derailOnNotification else { return [] }
        guard case .running(let session, _) = state else { return [] }
        return derail(session, cause: .notification, at: now)
    }

    private mutating func tick(at now: Date) -> [Effect] {
        switch state {
        case .idle:
            return startIfPossible(at: now)

        case .running(var session, let pending):
            if let pending = pending {
                guard now >= pending.due else { return [] }
                return derail(session, cause: .switchedTo(pending.toward), at: now)
            }
            // One car per tick at most: a Mac that slept without telling us
            // does not wake up to a pile of cars.
            guard now.timeIntervalSince(session.lastCarAt) >= rules.carInterval else { return [] }
            let car = Rules.car(at: session.cars.count)
            session.cars.append(car)
            session.lastCarAt = now
            state = .running(session, pending: nil)
            return [.carAdded(car, total: session.cars.count)]

        case .parked, .paused:
            return []
        }
    }

    private mutating func pause(at now: Date) -> [Effect] {
        switch state {
        case .paused:
            return []
        case .idle:
            state = .paused
            return [.paused(nil)]
        case .running(let session, _), .parked(let session, _):
            state = .paused
            return [.paused(run(from: session, endedAt: now, ending: .paused))]
        }
    }

    private mutating func resume(at now: Date) -> [Effect] {
        guard case .paused = state else { return [] }
        state = .idle
        return [.resumed] + startIfPossible(at: now)
    }

    private mutating func arrive(_ reason: StationReason, at now: Date) -> [Effect] {
        switch state {
        case .running(let session, _):
            state = .parked(session, reason)
            return [.parked(reason)]
        case .parked(let session, _):
            state = .parked(session, reason)
            return []
        case .idle, .paused:
            return []
        }
    }

    private mutating func depart(at now: Date) -> [Effect] {
        switch state {
        case .parked(var session, let reason):
            let returningToSameLine = frontmost.map { $0.bundleID == session.app.bundleID || rules.ridesAlong($0.bundleID) } ?? true
            if returningToSameLine {
                session.lastCarAt = now
                state = .running(session, pending: nil)
                return [.departed]
            }
            let retired = run(from: session, endedAt: now, ending: .retired(reason))
            state = .idle
            return [.retired(retired)] + startIfPossible(at: now)
        case .idle:
            return startIfPossible(at: now)
        case .running, .paused:
            return []
        }
    }

    // MARK: - Helpers

    /// Starts a train in the frontmost app. If the frontmost app is a
    /// passenger (Spotlight is open, say), the train leaves from `fallback`
    /// instead, when one is given: the app you were switching to, or the
    /// app you were just derailed in.
    private mutating func startIfPossible(at now: Date, fallback: App? = nil) -> [Effect] {
        guard case .idle = state else { return [] }
        var candidate = frontmost
        if let app = candidate, rules.ridesAlong(app.bundleID) {
            candidate = fallback
        }
        guard let app = candidate, !rules.ridesAlong(app.bundleID) else { return [] }
        state = .running(Session(app: app, startedAt: now), pending: nil)
        return [.sessionStarted(app)]
    }

    private mutating func derail(_ session: Session, cause: DerailCause, at now: Date) -> [Effect] {
        state = .idle
        let fallback: App
        switch cause {
        case .switchedTo(let app): fallback = app
        case .notification: fallback = session.app
        }
        if session.cars.isEmpty, case .switchedTo = cause {
            return [.rerouted(from: session.app)] + startIfPossible(at: now, fallback: fallback)
        }
        let wreck = Wreck(run: run(from: session, endedAt: now, ending: .derailed(cause)), cause: cause)
        return [.derailed(wreck)] + startIfPossible(at: now, fallback: fallback)
    }

    private func run(from session: Session, endedAt: Date, ending: Run.Ending) -> Run {
        Run(app: session.app, cars: session.carCount, startedAt: session.startedAt, endedAt: endedAt, ending: ending)
    }
}
