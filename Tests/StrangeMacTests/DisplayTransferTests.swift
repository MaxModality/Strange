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
        let actual = try await FrameTransition.prepare(source: current, destination: destination, tolerance: 0.5, move: { point in
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
            _ = try await FrameTransition.prepare(source: CGRect(x: 0, y: 0, width: 600, height: 800),
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
            try await FrameTransition.prepare(source: CGRect(x: 0, y: 0, width: 600, height: 800),
                destination: CGRect(x: 1600, y: 0, width: 900, height: 1600),
                tolerance: 1, move: { _ in withUnsafeCurrentTask { $0?.cancel() } },
                resize: { _ in resized = true }, readFrame: { XCTFail("Cancelled transfer must stop"); return .zero })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(resized)
    }

    func testRepeatingQuadrantAfterShrinkingRestoresFullSizeDespiteEdgeClamping() async throws {
        let quadrants: [WindowZone] = [.topLeftQuadrant, .topRightQuadrant, .bottomLeftQuadrant, .bottomRightQuadrant]
        for available in [CGRect(x: 0, y: 30, width: 1600, height: 900),
                          CGRect(x: -900, y: -1500, width: 900, height: 1500)] {
            for zone in quadrants {
                let destination = try ZoneGeometry.frame(for: zone, in: available, scale: 2)
                var current = destination
                for _ in 0..<3 {
                    current = try EdgeResize(original: current, direction: .shrink, in: available, scale: 2).idealFrame
                }
                XCTAssertLessThan(current.width, destination.width)
                XCTAssertLessThan(current.height, destination.height)
                var operations: [String] = []
                let actual = try await FrameTransition.prepare(source: current, destination: destination,
                    tolerance: 0.5, changesDisplay: false, move: { point in
                        operations.append("move")
                        current.origin = point
                    }, resize: { size in
                        operations.append("resize")
                        // Model an app that caps growth at the display's right/bottom edges.
                        current.size = CGSize(width: min(size.width, available.maxX - current.minX),
                                              height: min(size.height, available.maxY - current.minY))
                    }, readFrame: { current }, wait: { _ in XCTFail("Immediate match must not wait") })
                XCTAssertEqual(operations, ["move", "resize"], zone.rawValue)
                XCTAssertEqual(actual, destination, zone.rawValue)
            }
        }
    }

    func testQuadrantGrowCommandsExpandBeforeAndAfterShrinking() async throws {
        let available = CGRect(x: -900, y: -1500, width: 900, height: 1500)
        for zone: WindowZone in [.topLeftQuadrant, .topRightQuadrant, .bottomLeftQuadrant, .bottomRightQuadrant] {
            let quadrant = try ZoneGeometry.frame(for: zone, in: available, scale: 2)
            var current = quadrant
            // Exercise growth past the initial quadrant and regrowth after shrink.
            for direction in [ResizeDirection.grow, .shrink, .shrink, .grow] {
                let original = current
                let resize = try EdgeResize(original: original, direction: direction, in: available, scale: 2)
                let target = resize.idealFrame
                current = try await FrameTransition.prepare(source: current, destination: target,
                    tolerance: 0.5, changesDisplay: false, move: { current.origin = $0 }, resize: { size in
                        current.size = CGSize(width: min(size.width, available.maxX - current.minX),
                                              height: min(size.height, available.maxY - current.minY))
                    }, readFrame: { current }, wait: { _ in XCTFail("Immediate match must not wait") })
                // Complete the ordinary resize-first path when preparation was unnecessary.
                current.size = CGSize(width: min(target.width, available.maxX - current.minX),
                                      height: min(target.height, available.maxY - current.minY))
                current = try resize.frame(acceptedSize: current.size)
                XCTAssertEqual(current, target, "\(zone): \(direction)")
                if direction == .grow {
                    XCTAssertGreaterThan(current.width, original.width)
                    XCTAssertGreaterThan(current.height, original.height)
                } else {
                    XCTAssertLessThan(current.width, original.width)
                    XCTAssertLessThan(current.height, original.height)
                }
            }
            XCTAssertEqual(current, quadrant)
        }
    }

    func testSameDisplayShrinkOrIdenticalZoneNeedsNoPreparation() async throws {
        let source = CGRect(x: 0, y: 30, width: 1600, height: 900)
        for destination in [source, CGRect(x: 800, y: 480, width: 800, height: 450)] {
            let actual = try await FrameTransition.prepare(source: source, destination: destination,
                tolerance: 0.5, changesDisplay: false,
                move: { _ in XCTFail("No preparatory move needed") },
                resize: { _ in XCTFail("No preparatory resize needed") },
                readFrame: { XCTFail("No preparatory read needed"); return source })
            XCTAssertEqual(actual, source)
        }
    }

    func testMixedSizeChangeShrinksOverflowBeforeMovingAndGrowing() async throws {
        let available = CGRect(x: 0, y: 30, width: 1600, height: 900)
        var current = CGRect(x: 1200, y: 30, width: 400, height: 900)
        let destination = CGRect(x: 800, y: 480, width: 800, height: 450)
        var operations: [String] = []
        let actual = try await FrameTransition.prepare(source: current, destination: destination,
            tolerance: 0.5, changesDisplay: false, move: { point in
                operations.append("move")
                current.origin = point
                XCTAssertTrue(available.contains(current))
            }, resize: { size in
                operations.append("resize")
                current.size = CGSize(width: min(size.width, available.maxX - current.minX),
                                      height: min(size.height, available.maxY - current.minY))
            }, readFrame: { current }, wait: { _ in XCTFail("Immediate match must not wait") })
        XCTAssertEqual(operations, ["resize", "move", "resize"])
        XCTAssertEqual(actual, destination)
    }

    private func assertTransfer(source: CGRect, destination: CGRect) async throws {
        var current = source
        var onDestination = false
        var operations: [String] = []
        let actual = try await FrameTransition.prepare(source: source, destination: destination, tolerance: 0.5, move: { point in
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
