import Foundation
import CoreGraphics
import XCTest
@testable import StrangeCore

final class GeometryTests: XCTestCase {
    func testLandscapeZonesUseAvailableFrame() throws {
        let available = CGRect(x: 0, y: 25, width: 1440, height: 840)
        XCTAssertEqual(try ZoneGeometry.frame(for: .whole, in: available), available)
        XCTAssertEqual(try ZoneGeometry.frame(for: .rightHalf, in: available), CGRect(x: 720, y: 25, width: 720, height: 840))
        XCTAssertEqual(try ZoneGeometry.frame(for: .bottomHalf, in: available), CGRect(x: 0, y: 445, width: 1440, height: 420))
        XCTAssertEqual(try ZoneGeometry.frame(for: .centerThird, in: available), CGRect(x: 480, y: 25, width: 480, height: 840))
        XCTAssertEqual(try ZoneGeometry.frame(for: .leftTwoThirds, in: available), CGRect(x: 0, y: 25, width: 960, height: 840))
        XCTAssertEqual(try ZoneGeometry.frame(for: .rightTwoThirds, in: available), CGRect(x: 480, y: 25, width: 960, height: 840))
        XCTAssertEqual(try ZoneGeometry.frame(for: .bottomRightQuadrant, in: available), CGRect(x: 720, y: 445, width: 720, height: 420))
        XCTAssertEqual(try ZoneGeometry.frame(for: .topCenterSixth, in: available), CGRect(x: 480, y: 25, width: 480, height: 420))
    }

    func testPortraitThirdsRemainColumnsAndSixthsRemainThreeByTwo() throws {
        let available = CGRect(x: -900, y: -100, width: 900, height: 1500)
        XCTAssertEqual(try ZoneGeometry.frame(for: .leftThird, in: available), CGRect(x: -900, y: -100, width: 300, height: 1500))
        XCTAssertEqual(try ZoneGeometry.frame(for: .centerThird, in: available), CGRect(x: -600, y: -100, width: 300, height: 1500))
        XCTAssertEqual(try ZoneGeometry.frame(for: .rightThird, in: available), CGRect(x: -300, y: -100, width: 300, height: 1500))
        XCTAssertEqual(try ZoneGeometry.frame(for: .leftTwoThirds, in: available), CGRect(x: -900, y: -100, width: 600, height: 1500))
        XCTAssertEqual(try ZoneGeometry.frame(for: .rightTwoThirds, in: available), CGRect(x: -600, y: -100, width: 600, height: 1500))
        XCTAssertEqual(try ZoneGeometry.frame(for: .bottomCenterSixth, in: available), CGRect(x: -600, y: 650, width: 300, height: 750))
    }

    func testAllPartitionFamiliesTileWithoutGapsOrOverlaps() throws {
        let families: [[WindowZone]] = [
            [.whole], [.leftHalf, .rightHalf], [.topHalf, .bottomHalf],
            [.leftThird, .centerThird, .rightThird],
            [.leftTwoThirds, .rightThird], [.leftThird, .rightTwoThirds],
            [.topLeftQuadrant, .topRightQuadrant, .bottomLeftQuadrant, .bottomRightQuadrant],
            [.topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
        ]
        for available in [CGRect(x: -1511.25, y: 23.25, width: 1511.5, height: 899.5),
                          CGRect(x: 0, y: -1400, width: 777, height: 1399)] {
            for scale: CGFloat in [1, 2, 1.5] {
                for family in families {
                    let frames = try family.map { try ZoneGeometry.frame(for: $0, in: available, scale: scale) }
                    var union = CGRect.null
                    var area: CGFloat = 0
                    for (index, frame) in frames.enumerated() {
                        XCTAssertTrue(available.contains(frame), "\(family[index]) at scale \(scale): \(frame) outside \(available)")
                        union = union.union(frame)
                        area += frame.width * frame.height
                        for other in frames.dropFirst(index + 1) {
                            let overlap = frame.intersection(other)
                            XCTAssertTrue(overlap.isNull || overlap.width <= 0.000001 || overlap.height <= 0.000001,
                                          "Unexpected overlap: \(overlap)")
                        }
                        for boundary in [frame.minX, frame.maxX] where boundary != available.minX && boundary != available.maxX {
                            XCTAssertEqual(boundary * scale, (boundary * scale).rounded(), accuracy: 0.000001)
                        }
                        for boundary in [frame.minY, frame.maxY] where boundary != available.minY && boundary != available.maxY {
                            XCTAssertEqual(boundary * scale, (boundary * scale).rounded(), accuracy: 0.000001)
                        }
                    }
                    XCTAssertEqual(union, available)
                    XCTAssertEqual(area, available.width * available.height, accuracy: 0.000001)
                }
            }
        }
    }

    func testRejectsInvalidInputsAndCollapsedPixelPartitions() {
        for frame in [CGRect.zero, CGRect(x: 0, y: 0, width: -10, height: 10),
                      CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                      CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)] {
            XCTAssertThrowsError(try ZoneGeometry.frame(for: .whole, in: frame)) {
                XCTAssertEqual($0 as? GeometryError, .invalidRectangle)
            }
        }
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertThrowsError(try ZoneGeometry.frame(for: .whole, in: CGRect(x: 0, y: 0, width: 100, height: 100), scale: scale)) {
                XCTAssertEqual($0 as? GeometryError, .invalidScale)
            }
        }
        XCTAssertThrowsError(try ZoneGeometry.frame(for: .leftThird, in: CGRect(x: 0, y: 0, width: 1, height: 1))) {
            XCTAssertEqual($0 as? GeometryError, .unrepresentablePartition)
        }
    }

    func testDisplaySelectionUsesLargestOverlapAndStableTies() throws {
        let displays = [CGRect(x: -1000, y: 0, width: 1000, height: 1000),
                        CGRect(x: 0, y: 0, width: 1500, height: 1000)]
        XCTAssertEqual(try DisplayGeometry.index(containing: CGRect(x: -100, y: 100, width: 500, height: 500), in: displays), 1)
        XCTAssertEqual(try DisplayGeometry.index(containing: CGRect(x: -100, y: 100, width: 200, height: 500), in: displays), 0)
        XCTAssertEqual(try DisplayGeometry.index(containing: CGRect(x: -1400, y: 100, width: 100, height: 500), in: displays), 0)
        XCTAssertEqual(try DisplayGeometry.index(containing: CGRect(x: 2000, y: 100, width: 100, height: 500), in: displays), 1)
        XCTAssertNil(try DisplayGeometry.index(containing: CGRect(x: 0, y: 0, width: 100, height: 100), in: []))
        XCTAssertThrowsError(try DisplayGeometry.index(containing: CGRect.zero, in: displays))
    }

    func testAppKitConversionHandlesAboveBelowAndNegativeDisplays() throws {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(try CoordinateSpace.accessibilityFrame(fromAppKit: CGRect(x: 0, y: 50, width: 1440, height: 825), primaryDisplayFrame: primary),
                       CGRect(x: 0, y: 25, width: 1440, height: 825))
        XCTAssertEqual(try CoordinateSpace.accessibilityFrame(fromAppKit: CGRect(x: -900, y: 900, width: 900, height: 1600), primaryDisplayFrame: primary),
                       CGRect(x: -900, y: -1600, width: 900, height: 1600))
        XCTAssertEqual(try CoordinateSpace.accessibilityFrame(fromAppKit: CGRect(x: 0, y: -900, width: 1440, height: 900), primaryDisplayFrame: primary),
                       CGRect(x: 0, y: 900, width: 1440, height: 900))
    }
}
