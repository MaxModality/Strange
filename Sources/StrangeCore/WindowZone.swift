import Foundation
import CoreGraphics

/// Zones use a top-left origin, matching macOS Accessibility coordinates.
/// Thirds always form three columns, even on a portrait display.
public enum WindowZone: String, CaseIterable, Sendable {
    case whole
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird
    case topLeftQuadrant, topRightQuadrant, bottomLeftQuadrant, bottomRightQuadrant
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth

    var cell: (columns: Int, rows: Int, column: Int, row: Int) {
        switch self {
        case .whole: (1, 1, 0, 0)
        case .leftHalf: (2, 1, 0, 0)
        case .rightHalf: (2, 1, 1, 0)
        case .topHalf: (1, 2, 0, 0)
        case .bottomHalf: (1, 2, 0, 1)
        case .leftThird: (3, 1, 0, 0)
        case .centerThird: (3, 1, 1, 0)
        case .rightThird: (3, 1, 2, 0)
        case .topLeftQuadrant: (2, 2, 0, 0)
        case .topRightQuadrant: (2, 2, 1, 0)
        case .bottomLeftQuadrant: (2, 2, 0, 1)
        case .bottomRightQuadrant: (2, 2, 1, 1)
        case .topLeftSixth: (3, 2, 0, 0)
        case .topCenterSixth: (3, 2, 1, 0)
        case .topRightSixth: (3, 2, 2, 0)
        case .bottomLeftSixth: (3, 2, 0, 1)
        case .bottomCenterSixth: (3, 2, 1, 1)
        case .bottomRightSixth: (3, 2, 2, 1)
        }
    }
}

public enum GeometryError: Error, Equatable, Sendable {
    case invalidRectangle
    case invalidScale
    case unrepresentablePartition
}

public enum ZoneGeometry {
    /// Divide the available frame using shared pixel-rounded internal boundaries.
    /// The exact outer bounds are preserved, including fractional origins.
    public static func frame(for zone: WindowZone, in availableFrame: CGRect, scale: CGFloat = 1) throws -> CGRect {
        try validate(availableFrame)
        guard scale.isFinite, scale > 0 else { throw GeometryError.invalidScale }
        let cell = zone.cell
        let xs = try boundaries(origin: availableFrame.minX, length: availableFrame.width, count: cell.columns, scale: scale)
        let ys = try boundaries(origin: availableFrame.minY, length: availableFrame.height, count: cell.rows, scale: scale)
        return CGRect(x: xs[cell.column], y: ys[cell.row],
                      width: xs[cell.column + 1] - xs[cell.column],
                      height: ys[cell.row + 1] - ys[cell.row])
    }

    private static func boundaries(origin: CGFloat, length: CGFloat, count: Int, scale: CGFloat) throws -> [CGFloat] {
        var result = [origin]
        for index in 1..<count {
            let boundary = origin + length * (CGFloat(index) / CGFloat(count))
            let pixels = boundary * scale
            guard pixels.isFinite else { throw GeometryError.unrepresentablePartition }
            result.append(pixels.rounded() / scale)
        }
        result.append(origin + length)
        guard zip(result, result.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw GeometryError.unrepresentablePartition
        }
        return result
    }
}

func validate(_ frame: CGRect) throws {
    guard frame.origin.x.isFinite, frame.origin.y.isFinite,
          frame.size.width.isFinite, frame.size.height.isFinite,
          frame.size.width > 0, frame.size.height > 0,
          frame.maxX.isFinite, frame.maxY.isFinite else {
        throw GeometryError.invalidRectangle
    }
}
