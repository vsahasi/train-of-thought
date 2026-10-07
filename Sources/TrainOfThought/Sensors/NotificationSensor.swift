import AppKit

/// Notices notification banners by watching the window server.
///
/// `CGWindowListCopyWindowInfo` lists on-screen windows with their owner,
/// layer and bounds without any permission. While a banner is showing, the
/// Notification Center process has a window at a positive layer (on recent
/// macOS it is a full-screen host window that the banner is drawn into; on
/// older releases, a banner-sized window). When none was there and one
/// appears, a banner arrived. Desktop widgets live at a deeply negative
/// layer and are ignored. Nothing about the notification's content is read.
///
/// Opening the Notification Center panel from the clock also counts; that
/// is a distraction too.
///
/// Run the app with `--probe` to watch this sensor work.
final class NotificationSensor {
    var onBanner: (() -> Void)?

    private var timer: Timer?
    private var known: Set<Int> = []

    /// "Notification Center" on recent macOS, "NotificationCenter" on older.
    static func isNotificationCenter(_ owner: String) -> Bool {
        owner.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare("NotificationCenter") == .orderedSame
    }

    func start() {
        guard timer == nil else { return }
        known = Set(Self.bannerWindows().map { $0.id })
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = Set(Self.bannerWindows().map { $0.id })
        let fresh = current.subtracting(known)
        known = current
        if !fresh.isEmpty {
            onBanner?()
        }
    }

    struct BannerWindow {
        let id: Int
        let bounds: CGRect
        let level: Int
    }

    /// On-screen Notification Center windows at a positive layer: the
    /// banner host. Widgets (negative layers) are excluded.
    static func bannerWindows() -> [BannerWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String, isNotificationCenter(owner) else { return nil }
            guard let id = info[kCGWindowNumber as String] as? Int else { return nil }
            let level = info[kCGWindowLayer as String] as? Int ?? 0
            guard level > 0 else { return nil }
            var bounds = CGRect.zero
            if let dict = info[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: dict) { bounds = r }
            return BannerWindow(id: id, bounds: bounds, level: level)
        }
    }

    /// Prints every NotificationCenter window change until killed. For
    /// checking the sensor on a new macOS release.
    static func probe() -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("Watching NotificationCenter windows. Trigger a notification; ^C to stop.")
        print("All on-screen NotificationCenter windows are listed; * marks the ones that count as banners.")
        var last: [Int: String] = [:]
        while true {
            var current: [Int: String] = [:]
            if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                let banners = Set(bannerWindows().map { $0.id })
                for info in list where isNotificationCenter(info[kCGWindowOwnerName as String] as? String ?? "") {
                    let id = info[kCGWindowNumber as String] as? Int ?? 0
                    let level = info[kCGWindowLayer as String] as? Int ?? 0
                    var bounds = CGRect.zero
                    if let dict = info[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: dict) { bounds = r }
                    let mark = banners.contains(id) ? "*" : " "
                    current[id] = "\(mark) id=\(id) level=\(level) size=\(Int(bounds.width))x\(Int(bounds.height)) at (\(Int(bounds.minX)), \(Int(bounds.minY)))"
                }
            }
            if current != last {
                let stamp = ISO8601DateFormatter().string(from: Date())
                print("\(stamp)  \(current.count) window(s)")
                for (_, line) in current.sorted(by: { $0.key < $1.key }) { print("   \(line)") }
                last = current
            }
            usleep(200_000)
        }
    }
}
