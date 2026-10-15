import Foundation
import CoreGraphics
import XCTest
@testable import StrangeCore

final class AnchoredPlacementTests: XCTestCase {
    func testPortraitMinimumWidthAnchorsThirdsToLeftCenterAndRight() throws {
        let available = CGRect(x: -900, y: 25, width: 900, height: 1500)
        let size = CGSize(width: 600, height: 1500)
        XCTAssertEqual(try AnchoredPlacement.frame(for: .leftThird, acceptedSize: size, in: available),
                       CGRect(x: -900, y: 25, width: 600, height: 1500))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .centerThird, acceptedSize: size, in: available),
                       CGRect(x: -750, y: 25, width: 600, height: 1500))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .rightThird, acceptedSize: size, in: available),
                       CGRect(x: -600, y: 25, width: 600, height: 1500))
    }

    func testConstrainedTwoThirdsKeepTheirOuterEdges() throws {
        let available = CGRect(x: -900, y: 25, width: 900, height: 1500)
        let size = CGSize(width: 750, height: 1500)
        XCTAssertEqual(try AnchoredPlacement.frame(for: .leftTwoThirds, acceptedSize: size, in: available),
                       CGRect(x: -900, y: 25, width: 750, height: 1500))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .rightTwoThirds, acceptedSize: size, in: available),
                       CGRect(x: -750, y: 25, width: 750, height: 1500))
    }

    func testQuadrantsAndSixthsExpandInwardFromBothEdges() throws {
        let available = CGRect(x: -900, y: -1500, width: 900, height: 1500)
        let size = CGSize(width: 600, height: 950)
        let expectations: [(WindowZone, CGPoint)] = [
            (.topLeftQuadrant, CGPoint(x: -900, y: -1500)),
            (.topRightQuadrant, CGPoint(x: -600, y: -1500)),
            (.bottomLeftQuadrant, CGPoint(x: -900, y: -950)),
            (.bottomRightQuadrant, CGPoint(x: -600, y: -950)),
            (.topLeftSixth, CGPoint(x: -900, y: -1500)),
            (.topCenterSixth, CGPoint(x: -750, y: -1500)),
            (.topRightSixth, CGPoint(x: -600, y: -1500)),
            (.bottomLeftSixth, CGPoint(x: -900, y: -950)),
            (.bottomCenterSixth, CGPoint(x: -750, y: -950)),
            (.bottomRightSixth, CGPoint(x: -600, y: -950))
        ]
        for (zone, point) in expectations {
            let actual = try AnchoredPlacement.frame(for: zone, acceptedSize: size, in: available)
            XCTAssertEqual(actual, CGRect(origin: point, size: size), zone.rawValue)
            XCTAssertTrue(available.contains(actual), zone.rawValue)
        }
    }

    func testWholeAndFullWidthHalvesCenterHorizontally() throws {
        let available = CGRect(x: 100, y: 20, width: 900, height: 1500)
        let size = CGSize(width: 600, height: 1000)
        XCTAssertEqual(try AnchoredPlacement.frame(for: .whole, acceptedSize: size, in: available),
                       CGRect(x: 250, y: 270, width: 600, height: 1000))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .topHalf, acceptedSize: size, in: available),
                       CGRect(x: 250, y: 20, width: 600, height: 1000))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .bottomHalf, acceptedSize: size, in: available),
                       CGRect(x: 250, y: 520, width: 600, height: 1000))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .rightHalf, acceptedSize: size, in: available),
                       CGRect(x: 400, y: 270, width: 600, height: 1000))
    }

    func testIdealSizesKeepExactPartitionGeometry() throws {
        for available in [CGRect(x: -1511.25, y: 23.25, width: 1511.5, height: 899.5),
                          CGRect(x: -777, y: -1400, width: 777, height: 1399)] {
            for scale: CGFloat in [1, 2, 1.5] {
                for zone in WindowZone.allCases {
                    let ideal = try ZoneGeometry.frame(for: zone, in: available, scale: scale)
                    XCTAssertEqual(try AnchoredPlacement.frame(for: zone, acceptedSize: ideal.size,
                                                              in: available, scale: scale), ideal)
                }
            }
        }
    }

    func testFractionalOuterEdgesRemainExactAndCentersArePixelRounded() throws {
        let available = CGRect(x: -901.25, y: -1501.25, width: 901.5, height: 1501.5)
        let size = CGSize(width: 600.25, height: 950.25)
        let left = try AnchoredPlacement.frame(for: .topLeftQuadrant, acceptedSize: size, in: available, scale: 2)
        let right = try AnchoredPlacement.frame(for: .bottomRightQuadrant, acceptedSize: size, in: available, scale: 2)
        let center = try AnchoredPlacement.frame(for: .centerThird, acceptedSize: size, in: available, scale: 2)
        XCTAssertEqual(left.minX, available.minX)
        XCTAssertEqual(left.minY, available.minY)
        XCTAssertEqual(right.maxX, available.maxX)
        XCTAssertEqual(right.maxY, available.maxY)
        XCTAssertEqual(center.minX * 2, (center.minX * 2).rounded())
        XCTAssertEqual(center.minY * 2, (center.minY * 2).rounded())
        XCTAssertEqual(center.size, size)
        XCTAssertTrue(available.contains(center))
        // Rounding a nearly full-size window must not cross fractional edges.
        let nearlyFull = CGSize(width: 901.4, height: 1501.4)
        let clamped = try AnchoredPlacement.frame(for: .whole, acceptedSize: nearlyFull, in: available, scale: 1)
        XCTAssertGreaterThanOrEqual(clamped.minX, available.minX)
        XCTAssertLessThanOrEqual(clamped.maxX, available.maxX)
        XCTAssertGreaterThanOrEqual(clamped.minY, available.minY)
        XCTAssertLessThanOrEqual(clamped.maxY, available.maxY)
    }

    func testOversizedWindowsKeepPreferredAnchorWithoutShrinking() throws {
        let available = CGRect(x: -900, y: 25, width: 900, height: 1500)
        let size = CGSize(width: 1200, height: 1800)
        XCTAssertEqual(try AnchoredPlacement.frame(for: .topLeftSixth, acceptedSize: size, in: available),
                       CGRect(x: -900, y: 25, width: 1200, height: 1800))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .bottomRightQuadrant, acceptedSize: size, in: available),
                       CGRect(x: -1200, y: -275, width: 1200, height: 1800))
        XCTAssertEqual(try AnchoredPlacement.frame(for: .centerThird, acceptedSize: size, in: available),
                       CGRect(x: -1050, y: -125, width: 1200, height: 1800))
    }

    func testRejectsInvalidAcceptedSizesAndGeometry() {
        let available = CGRect(x: 0, y: 0, width: 900, height: 1500)
        for size in [CGSize.zero, CGSize(width: -1, height: 100),
                     CGSize(width: 100, height: 0), CGSize(width: CGFloat.nan, height: 100),
                     CGSize(width: 100, height: CGFloat.infinity)] {
            XCTAssertThrowsError(try AnchoredPlacement.frame(for: .rightThird, acceptedSize: size, in: available)) {
                XCTAssertEqual($0 as? GeometryError, .invalidRectangle)
            }
        }
        XCTAssertThrowsError(try AnchoredPlacement.frame(for: .rightThird, acceptedSize: available.size, in: .zero))
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertThrowsError(try AnchoredPlacement.frame(for: .whole, acceptedSize: available.size,
                                                           in: available, scale: scale)) {
                XCTAssertEqual($0 as? GeometryError, .invalidScale)
            }
        }
    }
}
