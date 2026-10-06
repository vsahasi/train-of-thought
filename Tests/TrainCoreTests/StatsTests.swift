import XCTest
@testable import TrainCore

final class StatsTests: XCTestCase {
    let xcode = App(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func run(cars: Int, minutes: Double, ending: Run.Ending = .derailed(.notification)) -> Run {
        Run(app: xcode, cars: cars, startedAt: t0, endedAt: t0.addingTimeInterval(minutes * 60), ending: ending)
    }

    func testBestRunIsByCarsThenDuration() {
        var stats = Stats()
        stats.record(run(cars: 3, minutes: 16))
        stats.record(run(cars: 3, minutes: 19))
        stats.record(run(cars: 2, minutes: 40))
        XCTAssertEqual(stats.bestRun?.cars, 3)
        XCTAssertEqual(stats.bestRun?.duration, 19 * 60)
        XCTAssertEqual(stats.totalCars, 8)
        XCTAssertEqual(stats.totalRuns, 3)
        XCTAssertEqual(stats.totalDerails, 3)
    }

    func testRunsWithoutCarsCountAsDerailsButNotRuns() {
        var stats = Stats()
        stats.record(run(cars: 0, minutes: 1))
        XCTAssertEqual(stats.totalDerails, 1)
        XCTAssertEqual(stats.totalRuns, 0)
        XCTAssertNil(stats.bestRun)
        XCTAssertTrue(stats.recentRuns.isEmpty)
    }

    func testHistoryIsCapped() {
        var stats = Stats()
        for i in 0..<(Stats.historyLimit + 10) {
            stats.record(run(cars: 1, minutes: Double(i)))
        }
        XCTAssertEqual(stats.recentRuns.count, Stats.historyLimit)
        XCTAssertEqual(stats.recentRuns.first?.duration, 10 * 60, "oldest runs fall off first")
        XCTAssertEqual(stats.totalRuns, Stats.historyLimit + 10, "totals are not capped")
    }

    func testCarsTodayOnlyCountsToday() {
        var stats = Stats()
        let now = Date()
        stats.record(Run(app: xcode, cars: 4, startedAt: now.addingTimeInterval(-1200), endedAt: now, ending: .paused))
        stats.record(Run(app: xcode, cars: 9, startedAt: now.addingTimeInterval(-90000), endedAt: now.addingTimeInterval(-86400 * 2), ending: .paused))
        XCTAssertEqual(stats.carsToday(now: now), 4)
    }

    func testStoreRoundTripsAndMissingFileIsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("train-of-thought-tests-\(UUID().uuidString)")
            .appendingPathComponent("stats.json")
        let store = StatsStore(url: url)
        XCTAssertEqual(store.load(), Stats())

        var stats = Stats()
        stats.record(run(cars: 7, minutes: 35, ending: .retired(.screenLocked)))
        stats.record(run(cars: 2, minutes: 10, ending: .derailed(.switchedTo(App(bundleID: "a.b", name: "B")))))
        do {
            try store.save(stats)
        } catch {
            XCTFail("save failed: \(error)")
        }
        XCTAssertEqual(store.load(), stats)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testCorruptFileLoadsAsEmpty() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tot-corrupt-\(UUID().uuidString).json")
        try? "not json".data(using: .utf8)?.write(to: url)
        XCTAssertEqual(StatsStore(url: url).load(), Stats())
        try? FileManager.default.removeItem(at: url)
    }
}
