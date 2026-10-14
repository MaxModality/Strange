import XCTest
import CoreGraphics
@testable import StrangeMac

final class PlacementTests: XCTestCase {
    func testTransientFailureRetriesThenSucceeds() async throws {
        var calls = 0
        let value = try await AccessibilityRetry.call {
            calls += 1
            if calls < 3 { throw PlacementError.accessibility(-25204) }
            return 42
        }
        XCTAssertEqual(value, 42)
        XCTAssertEqual(calls, 3)
    }

    func testRetryIsBounded() async {
        var calls = 0
        do {
            _ = try await AccessibilityRetry.call { () -> Int in
                calls += 1
                throw PlacementError.accessibility(-25204)
            }
            XCTFail("Must fail after three attempts")
        } catch { XCTAssertEqual(error as? PlacementError, .accessibility(-25204)) }
        XCTAssertEqual(calls, 3)
    }

    func testPermanentFailureIsNotRetried() async {
        var calls = 0
        do {
            _ = try await AccessibilityRetry.call { () -> Int in
                calls += 1
                throw PlacementError.unsupportedWindow
            }
            XCTFail("Must fail immediately")
        } catch { XCTAssertEqual(error as? PlacementError, .unsupportedWindow) }
        XCTAssertEqual(calls, 1)
    }

    func testVerificationRejectsClampedSizeAndInvalidValues() {
        let target = CGRect(x: -100, y: 30, width: 600, height: 900)
        XCTAssertTrue(FrameVerification.matches(target, target, tolerance: 0.5))
        XCTAssertFalse(FrameVerification.matches(CGRect(x: -100, y: 30, width: 650, height: 900), target, tolerance: 0.5))
        XCTAssertFalse(FrameVerification.matches(CGRect(x: CGFloat.nan, y: 30, width: 600, height: 900), target, tolerance: 0.5))
    }
}
