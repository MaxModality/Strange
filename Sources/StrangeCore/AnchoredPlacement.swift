import Foundation
import CoreGraphics

/// Positions the size an application accepts using the requested zone's edges.
/// Coordinates use the Accessibility top-left origin. Larger minimum sizes may
/// overlap adjacent zones, but stay on the display whenever they fit.
public enum AnchoredPlacement {
    public static func frame(for zone: WindowZone, acceptedSize: CGSize,
                             in availableFrame: CGRect, scale: CGFloat = 1) throws -> CGRect {
        let ideal = try ZoneGeometry.frame(for: zone, in: availableFrame, scale: scale)
        try validate(CGRect(origin: .zero, size: acceptedSize))
        // Preserve shared partition boundaries exactly for unconstrained windows.
        if acceptedSize == ideal.size { return ideal }

        let cell = zone.cell
        let horizontal: Anchor = cell.columns == 1 || cell.column == 1 && cell.columns == 3 && zone.columnSpan == 1
            ? .center : cell.column == 0 ? .leading : .trailing
        let vertical: Anchor = cell.rows == 1 ? .center : cell.row == 0 ? .leading : .trailing
        let x = try origin(anchor: horizontal, lower: availableFrame.minX,
                           upper: availableFrame.maxX, length: availableFrame.width,
                           accepted: acceptedSize.width, scale: scale)
        let y = try origin(anchor: vertical, lower: availableFrame.minY,
                           upper: availableFrame.maxY, length: availableFrame.height,
                           accepted: acceptedSize.height, scale: scale)
        let result = CGRect(origin: CGPoint(x: x, y: y), size: acceptedSize)
        try validate(result)
        return result
    }

    private enum Anchor { case leading, center, trailing }

    private static func origin(anchor: Anchor, lower: CGFloat, upper: CGFloat,
                               length: CGFloat, accepted: CGFloat, scale: CGFloat) throws -> CGFloat {
        let proposed: CGFloat
        switch anchor {
        case .leading: proposed = lower
        case .trailing: proposed = upper - accepted
        case .center:
            let pixels = (lower + (length - accepted) / 2) * scale
            guard pixels.isFinite else { throw GeometryError.unrepresentablePartition }
            proposed = pixels.rounded() / scale
        }
        // Oversized windows retain their intended edge or center. No position
        // can contain them without violating the application's accepted size.
        if accepted > length { return proposed }
        return min(max(proposed, lower), upper - accepted)
    }
}
