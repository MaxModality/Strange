import CoreGraphics

public enum ResizeDirection: Sendable, Equatable {
    case shrink, grow
}

/// A single relative resize in Accessibility coordinates. Each free side moves
/// by 5% of the usable display dimension; sides at its boundary remain fixed.
public struct EdgeResize: Sendable {
    public let idealFrame: CGRect
    private let available: CGRect
    private let horizontal: Axis
    private let vertical: Axis

    public init(original: CGRect, direction: ResizeDirection,
                in available: CGRect, scale: CGFloat = 1) throws {
        try validate(original)
        try validate(available)
        guard scale.isFinite, scale > 0, (1 / scale).isFinite else { throw GeometryError.invalidScale }
        self.available = available
        horizontal = try Axis(lower: original.minX, upper: original.maxX,
                              boundLower: available.minX, boundUpper: available.maxX,
                              direction: direction, scale: scale)
        vertical = try Axis(lower: original.minY, upper: original.maxY,
                            boundLower: available.minY, boundUpper: available.maxY,
                            direction: direction, scale: scale)
        idealFrame = CGRect(x: horizontal.lower, y: vertical.lower,
                            width: horizontal.upper - horizontal.lower,
                            height: vertical.upper - vertical.lower)
        try validate(idealFrame)
    }

    /// Keep touched sides anchored when the app imposes its own minimum size.
    /// Free axes stay centered on the ideal frame, contained whenever possible.
    public func frame(acceptedSize: CGSize) throws -> CGRect {
        try validate(CGRect(origin: .zero, size: acceptedSize))
        if acceptedSize == idealFrame.size { return idealFrame }
        let result = CGRect(x: horizontal.origin(for: acceptedSize.width, boundLower: available.minX, boundUpper: available.maxX),
                            y: vertical.origin(for: acceptedSize.height, boundLower: available.minY, boundUpper: available.maxY),
                            width: acceptedSize.width, height: acceptedSize.height)
        try validate(result)
        return result
    }

    private struct Axis: Sendable {
        let lower: CGFloat
        let upper: CGFloat
        let fixedLower: Bool
        let fixedUpper: Bool

        init(lower originalLower: CGFloat, upper originalUpper: CGFloat,
             boundLower: CGFloat, boundUpper: CGFloat, direction: ResizeDirection,
             scale: CGFloat) throws {
            let length = boundUpper - boundLower
            let pixel = 1 / scale
            // Bring offscreen geometry into this display before resizing.
            let size = min(originalUpper - originalLower, length)
            let start = min(max(originalLower, boundLower), boundUpper - size)
            let end = start + size
            fixedLower = start - boundLower <= pixel
            fixedUpper = boundUpper - end <= pixel
            let rawStep = length * 0.05 * scale
            guard rawStep.isFinite else { throw GeometryError.unrepresentablePartition }
            let step = max(1, rawStep.rounded()) / scale
            let freeCount = (fixedLower ? 0 : 1) + (fixedUpper ? 0 : 1)
            // Never cross the opposing side. The application's real minimum is
            // resolved by bounded Accessibility readback, without storing it.
            let inward = freeCount == 0 ? 0 : min(step, max(0, size - min(pixel, length)) / CGFloat(freeCount))
            switch direction {
            case .grow:
                lower = fixedLower ? boundLower : max(boundLower, start - step)
                upper = fixedUpper ? boundUpper : min(boundUpper, end + step)
            case .shrink:
                lower = fixedLower ? boundLower : start + inward
                upper = fixedUpper ? boundUpper : end - inward
            }
        }

        func origin(for size: CGFloat, boundLower: CGFloat, boundUpper: CGFloat) -> CGFloat {
            let proposed: CGFloat
            if fixedLower && !fixedUpper { proposed = boundLower }
            else if fixedUpper && !fixedLower { proposed = boundUpper - size }
            else { proposed = lower + ((upper - lower) - size) / 2 }
            if size > boundUpper - boundLower { return proposed }
            return min(max(proposed, boundLower), boundUpper - size)
        }
    }
}
