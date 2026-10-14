import Foundation
import CoreGraphics
import XCTest
@testable import StrangeCore

final class AvailableSpaceTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testHiddenBottomDockReclaimsStaleGapAndPreservesMenuBar() throws {
        let visible = CGRect(x: 0, y: 120, width: 1600, height: 850)
        let resolved = try AvailableSpace.frame(displayFrame: display, visibleFrame: visible,
                                               safeFrame: display, dockAutoHides: true, dockEdge: .bottom)
        XCTAssertEqual(resolved, CGRect(x: 0, y: 0, width: 1600, height: 970))
    }

    func testHiddenSideDockReclaimsOnlyItsEdge() throws {
        let visible = CGRect(x: 80, y: 10, width: 1430, height: 960)
        XCTAssertEqual(try AvailableSpace.frame(displayFrame: display, visibleFrame: visible,
                                               safeFrame: display, dockAutoHides: true, dockEdge: .left),
                       CGRect(x: 0, y: 10, width: 1510, height: 960))
        XCTAssertEqual(try AvailableSpace.frame(displayFrame: display, visibleFrame: visible,
                                               safeFrame: display, dockAutoHides: true, dockEdge: .right),
                       CGRect(x: 80, y: 10, width: 1520, height: 960))
    }

    func testSafeBoundsPreserveNotchAndClampDockExpansion() throws {
        let safe = CGRect(x: 5, y: 5, width: 1590, height: 940)
        let visible = CGRect(x: 0, y: 90, width: 1600, height: 880)
        XCTAssertEqual(try AvailableSpace.frame(displayFrame: display, visibleFrame: visible,
                                               safeFrame: safe, dockAutoHides: true, dockEdge: .bottom),
                       safe)
    }

    func testPortraitNegativeCoordinatesKeepThirdsLeftToRight() throws {
        let portrait = CGRect(x: -800, y: -1400, width: 780, height: 1400)
        let visible = CGRect(x: -800, y: -1320, width: 780, height: 1290)
        let resolved = try AvailableSpace.frame(displayFrame: portrait, visibleFrame: visible,
                                               safeFrame: portrait, dockAutoHides: true, dockEdge: .bottom)
        XCTAssertEqual(resolved, CGRect(x: -800, y: -1400, width: 780, height: 1370))
        // Convert only after resolving bottom-left AppKit geometry.
        let ax = try CoordinateSpace.accessibilityFrame(fromAppKit: resolved, primaryDisplayFrame: display)
        XCTAssertEqual(try ZoneGeometry.frame(for: .centerThird, in: ax),
                       CGRect(x: -540, y: 1030, width: 260, height: 1370))
    }

    func testVisibleDockPreservesReservedSpaceAtEveryEdge() throws {
        let visible = CGRect(x: 80, y: 100, width: 1440, height: 870)
        for edge in [DockEdge.bottom, .left, .right] {
            XCTAssertEqual(try AvailableSpace.frame(displayFrame: display, visibleFrame: visible,
                                                   safeFrame: display, dockAutoHides: false, dockEdge: edge),
                           visible)
        }
    }

    func testPartiallyOutsideMetadataIsClampedToDisplay() throws {
        let oversized = CGRect(x: -10, y: -10, width: 1620, height: 1020)
        XCTAssertEqual(try AvailableSpace.frame(displayFrame: display, visibleFrame: oversized,
                                               safeFrame: oversized, dockAutoHides: true, dockEdge: .bottom),
                       display)
    }

    func testRejectsInvalidAndDisjointMetadata() {
        let invalid = [CGRect.zero,
                       CGRect(x: 0, y: 0, width: -1, height: 100),
                       CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                       CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 100),
                       CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
                       CGRect(x: 2000, y: 0, width: 100, height: 100)]
        for value in invalid {
            for frames in [(value, display, display), (display, value, display), (display, display, value)] {
                XCTAssertThrowsError(try AvailableSpace.frame(displayFrame: frames.0, visibleFrame: frames.1,
                                                             safeFrame: frames.2, dockAutoHides: true, dockEdge: .bottom)) {
                    XCTAssertEqual($0 as? GeometryError, .invalidRectangle)
                }
            }
        }
        let bottom = CGRect(x: 0, y: 0, width: 1600, height: 300)
        let top = CGRect(x: 0, y: 700, width: 1600, height: 300)
        XCTAssertThrowsError(try AvailableSpace.frame(displayFrame: display, visibleFrame: bottom,
                                                     safeFrame: top, dockAutoHides: true, dockEdge: .bottom)) {
            XCTAssertEqual($0 as? GeometryError, .invalidRectangle)
        }
    }
}
