import XCTest
@testable import TrainCore

final class ShareTextTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(ShareText.format(30), "under a minute")
        XCTAssertEqual(ShareText.format(35 * 60), "35 min")
        XCTAssertEqual(ShareText.format(3600), "1 h")
        XCTAssertEqual(ShareText.format(3600 + 5 * 60 + 59), "1 h 05 min")
        XCTAssertEqual(ShareText.format(2 * 3600 + 30 * 60), "2 h 30 min")
    }

    func testEmojiTrainIsCapped() {
        XCTAssertEqual(ShareText.emojiTrain(cars: 0), "🚂")
        XCTAssertEqual(ShareText.emojiTrain(cars: 3), "🚂🚃🚃🚃")
        let long = ShareText.emojiTrain(cars: 40)
        XCTAssertEqual(long.filter { $0 == "🚃" }.count, ShareText.maxEmojiCars)
        XCTAssertTrue(long.hasSuffix("…"))
    }

    func testShareLine() {
        XCTAssertEqual(
            ShareText.train(cars: 7, duration: 35 * 60, appName: "Xcode"),
            "🚂🚃🚃🚃🚃🚃🚃🚃  7 cars · 35 min in Xcode\n" + ShareText.repoURL
        )
        XCTAssertEqual(
            ShareText.train(cars: 1, duration: 5 * 60, appName: "Zed", includeLink: false),
            "🚂🚃  1 car · 5 min in Zed"
        )
    }
}
