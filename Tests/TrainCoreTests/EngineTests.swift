import XCTest
@testable import TrainCore

final class EngineTests: XCTestCase {
    let xcode = App(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    let slack = App(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    let terminal = App(bundleID: "com.apple.Terminal", name: "Terminal")
    let spotlight = App(bundleID: "com.apple.Spotlight", name: "Spotlight")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// An engine already running a train in Xcode since t0.
    func runningEngine(rules: Rules = Rules()) -> Engine {
        var engine = Engine(rules: rules)
        XCTAssertEqual(engine.handle(.appActivated(xcode, at: t0)), [.sessionStarted(xcode)])
        return engine
    }

    // MARK: Rule 1: one app, one train

    func testFirstActivationStartsATrain() {
        var engine = Engine()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.handle(.appActivated(xcode, at: t0)), [.sessionStarted(xcode)])
        XCTAssertEqual(engine.session?.app, xcode)
        XCTAssertEqual(engine.session?.carCount, 0)
    }

    func testTickStartsATrainIfSomethingIsFrontmostAtLaunch() {
        var engine = Engine()
        XCTAssertEqual(engine.handle(.tick(at: t0)), [])
        _ = engine.handle(.pause(at: t0))
        _ = engine.handle(.appActivated(xcode, at: t0))
        XCTAssertNil(engine.session, "paused engines do not start trains")
        XCTAssertEqual(engine.handle(.resume(at: at(1))), [.resumed, .sessionStarted(xcode)])
    }

    func testPassengerAppsNeverStartATrain() {
        var engine = Engine()
        XCTAssertEqual(engine.handle(.appActivated(spotlight, at: t0)), [])
        XCTAssertEqual(engine.handle(.tick(at: at(1))), [])
        XCTAssertNil(engine.session)
    }

    // MARK: Rule 2: a car every N minutes

    func testCarsCoupleOnTheInterval() {
        var engine = runningEngine(rules: Rules(carInterval: 60))
        XCTAssertEqual(engine.handle(.tick(at: at(59))), [])
        XCTAssertEqual(engine.handle(.tick(at: at(60))), [.carAdded(Rules.car(at: 0), total: 1)])
        XCTAssertEqual(engine.handle(.tick(at: at(61))), [])
        XCTAssertEqual(engine.handle(.tick(at: at(120))), [.carAdded(Rules.car(at: 1), total: 2)])
        XCTAssertEqual(engine.session?.carCount, 2)
    }

    func testOnlyOneCarPerTickAfterALongGap() {
        var engine = runningEngine(rules: Rules(carInterval: 60))
        XCTAssertEqual(engine.handle(.tick(at: at(600))).count, 1)
        XCTAssertEqual(engine.session?.carCount, 1)
        XCTAssertEqual(engine.handle(.tick(at: at(601))), [], "the interval restarts from the last car")
    }

    func testCarKindsCycleAndEverySixthIsGold() {
        let cars = (0..<12).map { Rules.car(at: $0) }
        XCTAssertEqual(cars.map(\.kind).prefix(5), [.boxcar, .tanker, .hopper, .passenger, .flatbed])
        XCTAssertEqual(cars[5].kind, .boxcar)
        XCTAssertEqual(cars.filter(\.isGold).map(\.index), [5, 11])
    }

    // MARK: Rule 3: switching derails, after a grace

    func testSwitchingAwayBrakesThenDerailsAfterGrace() {
        var engine = runningEngine(rules: Rules(carInterval: 60, grace: 5))
        _ = engine.handle(.tick(at: at(60)))
        XCTAssertEqual(engine.handle(.appActivated(slack, at: at(100))), [.braking(toward: slack)])
        XCTAssertEqual(engine.handle(.tick(at: at(104))), [])
        let effects = engine.handle(.tick(at: at(105)))
        guard case .derailed(let wreck)? = effects.first else {
            return XCTFail("expected a derail, got \(effects)")
        }
        XCTAssertEqual(wreck.cause, .switchedTo(slack))
        XCTAssertEqual(wreck.run.cars, 1)
        XCTAssertEqual(wreck.run.app, xcode)
        XCTAssertEqual(wreck.run.startedAt, t0)
        XCTAssertEqual(wreck.run.endedAt, at(105))
        XCTAssertEqual(effects.last, .sessionStarted(slack), "a new train leaves in the app you switched to")
        XCTAssertEqual(engine.session?.app, slack)
        XCTAssertEqual(engine.session?.carCount, 0)
    }

    func testComingBackInsideTheGraceIsANearMiss() {
        var engine = runningEngine(rules: Rules(carInterval: 60, grace: 5))
        _ = engine.handle(.tick(at: at(60)))
        _ = engine.handle(.appActivated(slack, at: at(100)))
        XCTAssertEqual(engine.handle(.appActivated(xcode, at: at(103))), [.brakesReleased, .nearMiss])
        XCTAssertEqual(engine.handle(.tick(at: at(110))), [])
        XCTAssertEqual(engine.session?.app, xcode)
        XCTAssertEqual(engine.session?.carCount, 1, "the near miss kept the cars")
    }

    func testNoCarsCoupleWhileBraking() {
        var engine = runningEngine(rules: Rules(carInterval: 10, grace: 30))
        _ = engine.handle(.appActivated(slack, at: at(5)))
        XCTAssertEqual(engine.handle(.tick(at: at(20))), [])
        XCTAssertEqual(engine.session?.carCount, 0)
    }

    func testHoppingBetweenOtherAppsKeepsTheOriginalDueTime() {
        var engine = runningEngine(rules: Rules(grace: 5))
        _ = engine.handle(.appActivated(slack, at: at(100)))
        XCTAssertEqual(engine.handle(.appActivated(terminal, at: at(103))), [])
        let effects = engine.handle(.tick(at: at(105)))
        guard case .derailed(let wreck)? = effects.first else {
            return XCTFail("expected a derail, got \(effects)")
        }
        XCTAssertEqual(wreck.cause, .switchedTo(terminal))
        XCTAssertEqual(engine.session?.app, terminal)
    }

    func testZeroGraceDerailsImmediately() {
        var engine = runningEngine(rules: Rules(grace: 0))
        let effects = engine.handle(.appActivated(slack, at: at(10)))
        guard case .derailed? = effects.first else {
            return XCTFail("expected an immediate derail, got \(effects)")
        }
        XCTAssertEqual(effects.last, .sessionStarted(slack))
    }

    // MARK: Rule 4: notifications derail

    func testNotificationDerailsAndRestartsInTheSameApp() {
        var engine = runningEngine(rules: Rules(carInterval: 60))
        _ = engine.handle(.tick(at: at(60)))
        let effects = engine.handle(.notification(at: at(70)))
        guard case .derailed(let wreck)? = effects.first else {
            return XCTFail("expected a derail, got \(effects)")
        }
        XCTAssertEqual(wreck.cause, .notification)
        XCTAssertEqual(wreck.run.cars, 1)
        XCTAssertEqual(effects.last, .sessionStarted(xcode))
        XCTAssertEqual(engine.session?.carCount, 0)
    }

    func testNotificationRuleCanBeTurnedOff() {
        var engine = runningEngine(rules: Rules(derailOnNotification: false))
        XCTAssertEqual(engine.handle(.notification(at: at(1))), [])
        XCTAssertEqual(engine.session?.app, xcode)
    }

    func testNotificationWhileParkedDoesNothing() {
        var engine = runningEngine()
        _ = engine.handle(.stationArrive(.idle, at: at(1)))
        XCTAssertEqual(engine.handle(.notification(at: at(2))), [])
    }

    // MARK: Rule 5: passengers and crew

    func testPassengersDoNotDerail() {
        var engine = runningEngine(rules: Rules(grace: 5))
        XCTAssertEqual(engine.handle(.appActivated(spotlight, at: at(10))), [])
        XCTAssertEqual(engine.handle(.tick(at: at(30))), [])
        XCTAssertEqual(engine.session?.app, xcode)
    }

    func testCrewRidesAlongAndTheTrainStaysAttributed() {
        var engine = runningEngine(rules: Rules(carInterval: 60, grace: 5, crew: [terminal.bundleID]))
        XCTAssertEqual(engine.handle(.appActivated(terminal, at: at(10))), [])
        XCTAssertEqual(engine.handle(.tick(at: at(60))), [.carAdded(Rules.car(at: 0), total: 1)])
        XCTAssertEqual(engine.session?.app, xcode)
    }

    func testAPassengerDuringBrakingDoesNotSaveTheTrain() {
        var engine = runningEngine(rules: Rules(grace: 5))
        _ = engine.handle(.appActivated(slack, at: at(10)))
        XCTAssertEqual(engine.handle(.appActivated(spotlight, at: at(12))), [])
        let effects = engine.handle(.tick(at: at(15)))
        guard case .derailed? = effects.first else {
            return XCTFail("expected a derail, got \(effects)")
        }
        XCTAssertEqual(effects.last, .sessionStarted(slack), "a new train cannot leave from Spotlight")
    }

    // MARK: Rule 6: the station

    func testParkingFreezesTheTrainAndDepartingKeepsTheCars() {
        var engine = runningEngine(rules: Rules(carInterval: 60))
        _ = engine.handle(.tick(at: at(60)))
        XCTAssertEqual(engine.handle(.stationArrive(.screenLocked, at: at(70))), [.parked(.screenLocked)])
        XCTAssertEqual(engine.handle(.tick(at: at(700))), [], "no cars at the station")
        XCTAssertEqual(engine.handle(.appActivated(slack, at: at(800))), [], "no derails at the station either")
        _ = engine.handle(.appActivated(xcode, at: at(900)))
        XCTAssertEqual(engine.handle(.stationDepart(at: at(1000))), [.departed])
        XCTAssertEqual(engine.session?.carCount, 1)
        XCTAssertEqual(engine.handle(.tick(at: at(1030))), [], "the car clock restarts on departure")
        XCTAssertEqual(engine.handle(.tick(at: at(1060))).count, 1)
    }

    func testParkingClearsAPendingDerail() {
        var engine = runningEngine(rules: Rules(grace: 5))
        _ = engine.handle(.appActivated(slack, at: at(10)))
        _ = engine.handle(.appActivated(xcode, at: at(11)))
        _ = engine.handle(.stationArrive(.sleep, at: at(12)))
        _ = engine.handle(.stationDepart(at: at(500)))
        XCTAssertEqual(engine.handle(.tick(at: at(501))), [])
        XCTAssertEqual(engine.session?.app, xcode)
    }

    func testDepartingIntoADifferentAppRetiresQuietly() {
        var engine = runningEngine(rules: Rules(carInterval: 60))
        _ = engine.handle(.tick(at: at(60)))
        _ = engine.handle(.stationArrive(.idle, at: at(70)))
        _ = engine.handle(.appActivated(slack, at: at(80)))
        let effects = engine.handle(.stationDepart(at: at(90)))
        XCTAssertEqual(effects.count, 2)
        guard case .retired(let run)? = effects.first else {
            return XCTFail("expected a retirement, got \(effects)")
        }
        XCTAssertEqual(run.cars, 1)
        XCTAssertEqual(run.ending, .retired(.idle))
        XCTAssertEqual(run.endedAt, at(90))
        XCTAssertEqual(effects.last, .sessionStarted(slack))
    }

    func testDepartingWhileAPassengerIsFrontmostCountsAsTheSameLine() {
        var engine = runningEngine()
        _ = engine.handle(.stationArrive(.idle, at: at(10)))
        _ = engine.handle(.appActivated(spotlight, at: at(20)))
        XCTAssertEqual(engine.handle(.stationDepart(at: at(21))), [.departed])
        XCTAssertEqual(engine.session?.app, xcode)
    }

    func testStationEventsWhenIdleAreHarmless() {
        var engine = Engine()
        XCTAssertEqual(engine.handle(.stationArrive(.idle, at: t0)), [])
        XCTAssertEqual(engine.handle(.stationDepart(at: at(1))), [])
        _ = engine.handle(.appActivated(spotlight, at: at(2)))
        XCTAssertEqual(engine.handle(.stationDepart(at: at(3))), [])
    }

    // MARK: Rule 7: pause

    func testPauseEndsTheRunAndResumeStartsFresh() {
        var engine = runningEngine(rules: Rules(carInterval: 60))
        _ = engine.handle(.tick(at: at(60)))
        let effects = engine.handle(.pause(at: at(70)))
        guard case .paused(let run?)? = effects.first else {
            return XCTFail("expected a paused run, got \(effects)")
        }
        XCTAssertEqual(run.cars, 1)
        XCTAssertEqual(run.ending, .paused)
        XCTAssertTrue(engine.isPaused)
        XCTAssertEqual(engine.handle(.appActivated(slack, at: at(80))), [])
        XCTAssertEqual(engine.handle(.notification(at: at(81))), [])
        XCTAssertEqual(engine.handle(.tick(at: at(200))), [])
        XCTAssertEqual(engine.handle(.pause(at: at(201))), [])
        XCTAssertEqual(engine.handle(.resume(at: at(300))), [.resumed, .sessionStarted(slack)])
        XCTAssertEqual(engine.session?.carCount, 0)
    }

    func testPausingWhileIdleReportsNoRun() {
        var engine = Engine()
        XCTAssertEqual(engine.handle(.pause(at: t0)), [.paused(nil)])
        XCTAssertEqual(engine.handle(.resume(at: at(1))), [.resumed])
        XCTAssertEqual(engine.state, .idle)
    }
}
