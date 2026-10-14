import CoreGraphics
import XCTest
import StrangeCore
@testable import StrangeMac

@MainActor final class DisplayTransferTests: XCTestCase {
    func testLandscapeToPortraitUsesReclaimedDockSpaceAfterRelocation() async throws {
        let source = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let portrait = CGRect(x: -900, y: -400, width: 900, height: 1600)
        let visible = CGRect(x: -900, y: -300, width: 900, height: 1470)
        let available = try AvailableSpace.frame(displayFrame: portrait, visibleFrame: visible,
                                                 safeFrame: portrait, dockAutoHides: true, dockEdge: .bottom)
        let destination = try CoordinateSpace.accessibilityFrame(fromAppKit: available, primaryDisplayFrame: source)
        XCTAssertEqual(destination, CGRect(x: -900, y: -270, width: 900, height: 1570))
        try await assertTransfer(source: source, destination: destination)
    }

    func testPortraitToLandscapeExpandsWidthAfterRelocation() async throws {
        try await assertTransfer(source: CGRect(x: -900, y: -270, width: 900, height: 1570),
                                 destination: CGRect(x: 0, y: 30, width: 1600, height: 870))
    }

    func testEqualSizeStillResizesAfterMoveChangesWindowSize() async throws {
        let destination = CGRect(x: 1600, y: 30, width: 1600, height: 870)
        var current = CGRect(x: 0, y: 30, width: 1600, height: 870)
        var resized = false
        let actual = try await DisplayTransfer.prepare(source: current, destination: destination, tolerance: 0.5, move: { point in
            current.origin = point
            current.size.height -= 100 // macOS adjusts dimensions during relocation.
        }, resize: { size in
            resized = true
            current.size = size
        }, readFrame: { current }, wait: { _ in XCTFail("Immediate success must not wait") })
        XCTAssertTrue(resized)
        XCTAssertEqual(actual, destination)
    }

    func testFailedRelocationNeverExpandsWindowOnSourceDisplay() async {
        var resized = false
        do {
            _ = try await DisplayTransfer.prepare(source: CGRect(x: 0, y: 0, width: 600, height: 800),
                destination: CGRect(x: 1600, y: 0, width: 900, height: 1600),
                tolerance: 1, move: { _ in throw PlacementError.focusChanged },
                resize: { _ in resized = true }, readFrame: { XCTFail("Must stop after failed move"); return .zero })
            XCTFail("Transfer must propagate loss of focus")
        } catch { XCTAssertEqual(error as? PlacementError, .focusChanged) }
        XCTAssertFalse(resized)
    }

    func testCancellationAfterRelocationPreventsResize() async {
        var resized = false
        let task = Task {
            try await DisplayTransfer.prepare(source: CGRect(x: 0, y: 0, width: 600, height: 800),
                destination: CGRect(x: 1600, y: 0, width: 900, height: 1600),
                tolerance: 1, move: { _ in withUnsafeCurrentTask { $0?.cancel() } },
                resize: { _ in resized = true }, readFrame: { XCTFail("Cancelled transfer must stop"); return .zero })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(resized)
    }

    private func assertTransfer(source: CGRect, destination: CGRect) async throws {
        var current = source
        var onDestination = false
        var operations: [String] = []
        let actual = try await DisplayTransfer.prepare(source: source, destination: destination, tolerance: 0.5, move: { point in
            operations.append("move")
            XCTAssertLessThanOrEqual(current.width, destination.width)
            XCTAssertLessThanOrEqual(current.height, destination.height)
            onDestination = true
            current.origin = point
        }, resize: { size in
            operations.append("resize")
            // Model an app that caps dimensions at whichever screen owns it.
            let limit = onDestination ? destination.size : source.size
            current.size = CGSize(width: min(size.width, limit.width), height: min(size.height, limit.height))
        }, readFrame: {
            operations.append("read")
            return current
        }, wait: { _ in XCTFail("Immediate success must not wait") })
        XCTAssertEqual(operations, ["resize", "read", "move", "resize", "read"])
        XCTAssertEqual(actual, destination)
    }
}
