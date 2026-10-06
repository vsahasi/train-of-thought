import Foundation

/// The train as text, for the clipboard and for anywhere emoji go.
public enum ShareText {
    public static let repoURL = "https://github.com/vsahasi/train-of-thought"

    /// Emoji cars beyond this many are summarised to keep tweets tweetable.
    public static let maxEmojiCars = 24

    public static func train(cars: Int, duration: TimeInterval, appName: String, includeLink: Bool = true) -> String {
        var line = emojiTrain(cars: cars)
        line += "  \(cars) \(cars == 1 ? "car" : "cars") · \(format(duration)) in \(appName)"
        return includeLink ? line + "\n" + repoURL : line
    }

    public static func emojiTrain(cars: Int) -> String {
        let shown = min(max(cars, 0), maxEmojiCars)
        var s = "🚂" + String(repeating: "🚃", count: shown)
        if cars > maxEmojiCars {
            s += "…"
        }
        return s
    }

    /// "35 min", "1 h 05 min", "2 h", "under a minute".
    public static func format(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 {
            return minutes == 0 ? "under a minute" : "\(minutes) min"
        }
        if minutes == 0 {
            return "\(hours) h"
        }
        return String(format: "%d h %02d min", hours, minutes)
    }
}
