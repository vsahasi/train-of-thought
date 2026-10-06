import Foundation

/// Everything the app remembers. Lives in one JSON file, never leaves
/// the machine.
public struct Stats: Codable, Equatable {
    public var bestRun: Run?
    public var totalCars: Int
    public var totalDerails: Int
    public var totalRuns: Int
    /// Most recent last. Capped at `historyLimit`.
    public var recentRuns: [Run]

    public static let historyLimit = 500

    public init() {
        bestRun = nil
        totalCars = 0
        totalDerails = 0
        totalRuns = 0
        recentRuns = []
    }

    /// Records a finished train. Runs with no cars are not remembered: a
    /// ten-second visit to Finder is not a run.
    public mutating func record(_ run: Run) {
        if case .derailed = run.ending {
            totalDerails += 1
        }
        guard run.cars > 0 else { return }
        totalRuns += 1
        totalCars += run.cars
        recentRuns.append(run)
        if recentRuns.count > Stats.historyLimit {
            recentRuns.removeFirst(recentRuns.count - Stats.historyLimit)
        }
        if let best = bestRun {
            if run.cars > best.cars || (run.cars == best.cars && run.duration > best.duration) {
                bestRun = run
            }
        } else {
            bestRun = run
        }
    }

    public func carsToday(calendar: Calendar = .current, now: Date = Date()) -> Int {
        recentRuns
            .filter { calendar.isDate($0.endedAt, inSameDayAs: now) }
            .reduce(0) { $0 + $1.cars }
    }
}

/// Reads and writes `Stats` as JSON. The default location is
/// `~/Library/Application Support/Train of Thought/stats.json`.
public struct StatsStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Train of Thought", isDirectory: true).appendingPathComponent("stats.json")
    }

    public func load() -> Stats {
        guard let data = try? Data(contentsOf: url) else { return Stats() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Stats.self, from: data)) ?? Stats()
    }

    public func save(_ stats: Stats) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stats).write(to: url, options: .atomic)
    }
}
