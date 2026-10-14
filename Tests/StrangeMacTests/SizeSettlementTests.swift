import CoreGraphics
import XCTest
@testable import StrangeMac

@MainActor final class SizeSettlementTests: XCTestCase {
    func testImmediateMatchDoesNotWait() async throws {
        var reads = 0
        var waits: [Duration] = []
        let result = try await SizeSettlement.read(requested: CGSize(width: 640, height: 1400), tolerance: 0.5, readFrame: {
            reads += 1
            return CGRect(x: 0, y: 0, width: 640.5, height: 1400)
        }, wait: { waits.append($0) })
        XCTAssertTrue(result.isStable)
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(waits.isEmpty)
    }

    func testAnimationReadbacksReachRequestedSizeBeforeAnchoring() async throws {
        let sizes = [CGSize(width: 320, height: 800), CGSize(width: 480, height: 1100), CGSize(width: 640, height: 1400)]
        var reads = 0
        var waits: [Duration] = []
        let result = try await SizeSettlement.read(requested: sizes[2], tolerance: 0.5, readFrame: {
            defer { reads += 1 }
            return CGRect(origin: .zero, size: sizes[reads])
        }, wait: { waits.append($0) })
        XCTAssertTrue(result.isStable)
        XCTAssertEqual(result.frame.size, sizes[2])
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(waits, [.milliseconds(16), .milliseconds(32)])
    }

    func testRefusedShrinkReturnsTheStableAcceptedMinimum() async throws {
        let accepted = CGSize(width: 520, height: 1200)
        var reads = 0
        var waits: [Duration] = []
        let result = try await SizeSettlement.read(requested: CGSize(width: 260, height: 1200), tolerance: 0.5, readFrame: {
            reads += 1
            return CGRect(origin: .zero, size: accepted)
        }, wait: { waits.append($0) })
        XCTAssertTrue(result.isStable)
        XCTAssertEqual(result.frame.size, accepted)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(waits, [.milliseconds(16)])
    }

    func testChangingReadbacksCannotPollForever() async throws {
        var reads = 0
        var waits: [Duration] = []
        let result = try await SizeSettlement.read(requested: CGSize(width: 640, height: 1400), tolerance: 0.5, readFrame: {
            reads += 1
            return CGRect(x: 0, y: 0, width: 100 + reads * 20, height: 800)
        }, wait: { waits.append($0) })
        XCTAssertFalse(result.isStable)
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(waits.count, 2)
    }

    func testCancelledWaitStopsFurtherReadbacks() async {
        var reads = 0
        do {
            _ = try await SizeSettlement.read(requested: CGSize(width: 640, height: 1400), tolerance: 0.5, readFrame: {
                reads += 1
                return CGRect(x: 0, y: 0, width: 320, height: 800)
            }, wait: { _ in throw CancellationError() })
            XCTFail("Cancelled settling must stop")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }
}
