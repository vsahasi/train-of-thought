// A very small stand-in for XCTest, used only by Scripts/test-clt.sh on Macs
// that have the Command Line Tools but not Xcode (the Command Line Tools do
// not ship XCTest). With Xcode installed, `swift test` uses the real thing.
//
// It covers exactly the assertions the test suite uses. Keep it that way.

@_exported import Foundation

public var xctestShimFailures: [String] = []

open class XCTestCase: NSObject {
    public required override init() { super.init() }
    open func setUp() {}
    open func tearDown() {}
}

private func record(_ message: String, _ file: StaticString, _ line: UInt) {
    xctestShimFailures.append("\(file):\(line): \(message)")
}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record("XCTFail \(message)", file, line)
}

public func XCTAssertEqual<T: Equatable>(
    _ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line
) {
    let (x, y) = (a(), b())
    if x != y { record("XCTAssertEqual failed: (\(x)) is not equal to (\(y)) \(message())", file, line) }
}

public func XCTAssertTrue(_ v: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !v() { record("XCTAssertTrue failed \(message())", file, line) }
}

public func XCTAssertFalse(_ v: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if v() { record("XCTAssertFalse failed \(message())", file, line) }
}

public func XCTAssertNil<T>(_ v: @autoclosure () -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let x = v() { record("XCTAssertNil failed: \(x) \(message())", file, line) }
}

public func XCTAssertNotNil<T>(_ v: @autoclosure () -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if v() == nil { record("XCTAssertNotNil failed \(message())", file, line) }
}
