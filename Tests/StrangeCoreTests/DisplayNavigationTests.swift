import Foundation
import CoreGraphics
import XCTest
@testable import StrangeCore

final class DisplayNavigationTests: XCTestCase {
    func testUnorderedLandscapeAndPortraitDisplaysNavigateSpatially() throws {
        let frames = [CGRect(x: 1600, y: 100, width: 900, height: 1600),
                      CGRect(x: -1200, y: -200, width: 1200, height: 800),
                      CGRect(x: 0, y: 0, width: 1600, height: 900)]
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 2, direction: .left, in: frames), 1)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 2, direction: .right, in: frames), 0)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 1, direction: .right, in: frames), 2)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 0, direction: .left, in: frames), 2)
    }

    func testNavigationWrapsAtBothEnds() throws {
        let frames = [CGRect(x: -1000, y: 0, width: 1000, height: 700),
                      CGRect(x: 0, y: 0, width: 1400, height: 900),
                      CGRect(x: 1400, y: 0, width: 1000, height: 700)]
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 0, direction: .left, in: frames), 2)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 2, direction: .right, in: frames), 0)
    }

    func testVerticalAlignmentUsesTopToBottomAccessibilityCoordinates() throws {
        let frames = [CGRect(x: 0, y: 900, width: 1400, height: 900),
                      CGRect(x: 0, y: -900, width: 1400, height: 900),
                      CGRect(x: 0, y: 0, width: 1400, height: 900)]
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 1, direction: .right, in: frames), 2)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 2, direction: .right, in: frames), 0)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 0, direction: .left, in: frames), 2)
    }

    func testIdenticalOriginsKeepInputOrder() throws {
        let frames = [CGRect(x: 0, y: 0, width: 1000, height: 700),
                      CGRect(x: 0, y: 0, width: 700, height: 1000),
                      CGRect(x: 0, y: 0, width: 1400, height: 900)]
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 0, direction: .right, in: frames), 1)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 1, direction: .right, in: frames), 2)
        XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 2, direction: .right, in: frames), 0)
    }

    func testSingleDisplayReturnsItselfAndEmptyReturnsNil() throws {
        let frames = [CGRect(x: 0, y: 0, width: 1400, height: 900)]
        for direction in [DisplayDirection.left, .right] {
            XCTAssertEqual(try DisplayNavigation.destinationIndex(from: 0, direction: direction, in: frames), 0)
            XCTAssertNil(try DisplayNavigation.destinationIndex(from: 0, direction: direction, in: []))
            XCTAssertNil(try DisplayNavigation.destinationIndex(from: -1, direction: direction, in: []))
        }
    }

    func testRejectsInvalidSourceIndices() {
        let frames = [CGRect(x: 0, y: 0, width: 1400, height: 900)]
        for index in [-1, 1, Int.max] {
            XCTAssertThrowsError(try DisplayNavigation.destinationIndex(from: index, direction: .right, in: frames)) {
                XCTAssertEqual($0 as? DisplayNavigationError, .invalidSourceIndex)
            }
        }
    }

    func testRejectsInvalidDisplayGeometryBeforeSorting() {
        let valid = CGRect(x: 0, y: 0, width: 1400, height: 900)
        for invalid in [CGRect.zero,
                        CGRect(x: 0, y: 0, width: -100, height: 100),
                        CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                        CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 100),
                        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)] {
            XCTAssertThrowsError(try DisplayNavigation.destinationIndex(from: 0, direction: .right, in: [valid, invalid])) {
                XCTAssertEqual($0 as? GeometryError, .invalidRectangle)
            }
        }
    }

    func testCommandLabelsDescribeWholeDisplayPlacement() {
        XCTAssertEqual(WindowCommand.zone(.leftThird).label, "leftThird")
        XCTAssertEqual(WindowCommand.moveDisplay(.left).label, "Previous display (whole)")
        XCTAssertEqual(WindowCommand.moveDisplay(.right).label, "Next display (whole)")
    }
}
