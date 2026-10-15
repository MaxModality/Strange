import CoreGraphics
import XCTest
@testable import StrangeCore

final class EdgeResizeTests: XCTestCase {
    private let display = CGRect(x: 0, y: 20, width: 1000, height: 800)

    func testFloatingWindowChangesEveryFreeSide() throws {
        let original = CGRect(x: 200, y: 220, width: 400, height: 300)
        XCTAssertEqual(try resize(original, .grow), CGRect(x: 150, y: 180, width: 500, height: 380))
        XCTAssertEqual(try resize(original, .shrink), CGRect(x: 250, y: 260, width: 300, height: 220))
    }

    func testAllCornersKeepTouchingSidesAnchored() throws {
        for right in [false, true] {
            for bottom in [false, true] {
                let original = CGRect(x: right ? 600 : 0, y: bottom ? 520 : 20, width: 400, height: 300)
                for direction in [ResizeDirection.grow, .shrink] {
                    let result = try resize(original, direction)
                    XCTAssertEqual(right ? result.maxX : result.minX, right ? 1000 : 0)
                    XCTAssertEqual(bottom ? result.maxY : result.minY, bottom ? 820 : 20)
                    XCTAssertEqual(result.width, direction == .grow ? 450 : 350)
                    XCTAssertEqual(result.height, direction == .grow ? 340 : 260)
                }
            }
        }
    }

    func testOpposingEdgesFreezeOnlyThatDimensionAndWholeIsUnchanged() throws {
        for direction in [ResizeDirection.grow, .shrink] {
            let fullHeight = try resize(CGRect(x: 200, y: 20, width: 400, height: 800), direction)
            XCTAssertEqual(fullHeight.minY, 20)
            XCTAssertEqual(fullHeight.height, 800)
            XCTAssertNotEqual(fullHeight.width, 400)
            let fullWidth = try resize(CGRect(x: 0, y: 220, width: 1000, height: 300), direction)
            XCTAssertEqual(fullWidth.minX, 0)
            XCTAssertEqual(fullWidth.width, 1000)
            XCTAssertNotEqual(fullWidth.height, 300)
            XCTAssertEqual(try resize(display, direction), display)
        }
    }

    func testGrowthClampsAndNewlyTouchedEdgeStaysFixedOnShrink() throws {
        let grown = try resize(CGRect(x: 25, y: 50, width: 500, height: 400), .grow)
        XCTAssertEqual(grown.minX, 0)
        XCTAssertEqual(grown.minY, 20)
        let shrunk = try resize(grown, .shrink)
        XCTAssertEqual(shrunk.minX, 0)
        XCTAssertEqual(shrunk.minY, 20)
        XCTAssertLessThan(shrunk.width, grown.width)
    }

    func testTinyWindowNeverCollapses() throws {
        var frame = CGRect(x: 200, y: 200, width: 10, height: 10)
        for _ in 0..<20 { frame = try resize(frame, .shrink, scale: 2) }
        XCTAssertEqual(frame.width, 0.5)
        XCTAssertEqual(frame.height, 0.5)
        XCTAssertTrue(display.contains(frame))
    }

    func testAcceptedMinimumPreservesAnchorOrFloatingCenter() throws {
        let anchored = try EdgeResize(original: CGRect(x: 600, y: 520, width: 400, height: 300),
                                      direction: .shrink, in: display)
        let constrained = try anchored.frame(acceptedSize: CGSize(width: 500, height: 400))
        XCTAssertEqual(constrained, CGRect(x: 500, y: 420, width: 500, height: 400))
        let floating = try EdgeResize(original: CGRect(x: 300, y: 220, width: 400, height: 300),
                                      direction: .grow, in: display)
        let capped = try floating.frame(acceptedSize: CGSize(width: 420, height: 320))
        XCTAssertEqual(capped.midX, 500)
        XCTAssertEqual(capped.midY, 370)
    }

    func testNegativePortraitDisplayAndRetinaTolerance() throws {
        let bounds = CGRect(x: -900, y: -400, width: 900, height: 1600)
        let original = CGRect(x: -899.75, y: -399.75, width: 400, height: 600)
        let result = try EdgeResize(original: original, direction: .grow, in: bounds, scale: 2).idealFrame
        XCTAssertEqual(result.minX, -900)
        XCTAssertEqual(result.minY, -400)
        XCTAssertTrue(bounds.contains(result))
        let fractional = try EdgeResize(original: CGRect(x: -500.25, y: 0.25, width: 200, height: 400),
                                        direction: .grow, in: bounds, scale: 2).idealFrame
        XCTAssertEqual(fractional.minX, -545.25)
        XCTAssertEqual(fractional.minY, -79.75)
    }

    func testOffscreenWindowIsFittedAndNumericInputsAreValidated() throws {
        let result = try resize(CGRect(x: -300, y: -200, width: 2000, height: 1000), .grow)
        XCTAssertEqual(result, display)
        for scale in [CGFloat.zero, -1, .infinity, .nan] {
            XCTAssertThrowsError(try resize(display, .grow, scale: scale))
        }
        XCTAssertThrowsError(try resize(CGRect(x: 0, y: 0, width: 0, height: 20), .grow))
        XCTAssertThrowsError(try resize(CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20), .grow))
    }

    private func resize(_ frame: CGRect, _ direction: ResizeDirection, scale: CGFloat = 1) throws -> CGRect {
        try EdgeResize(original: frame, direction: direction, in: display, scale: scale).idealFrame
    }
}
