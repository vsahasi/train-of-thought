// Runs one test method and reports. Used only by Scripts/test-clt.sh, which
// generates the list of calls from the test sources (the way XCTest does on
// Linux) because the Objective-C runtime cannot see Swift test methods
// outside the real XCTest.

import Foundation
import XCTest

public var xctestShimPassed = 0
public var xctestShimFailed = 0

public func xctestShimRun(_ name: String, _ body: () -> Void) {
    xctestShimFailures = []
    body()
    if xctestShimFailures.isEmpty {
        xctestShimPassed += 1
        print("  ✓ \(name)")
    } else {
        xctestShimFailed += 1
        print("  ✗ \(name)")
        for f in xctestShimFailures { print("      \(f)") }
    }
}

public func xctestShimFinish() -> Never {
    print("\n\(xctestShimPassed) passed, \(xctestShimFailed) failed")
    exit(xctestShimFailed == 0 ? 0 : 1)
}
