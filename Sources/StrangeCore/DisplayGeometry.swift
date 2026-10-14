import Foundation
import CoreGraphics

public enum DisplayGeometry {
    /// Select the display with the largest overlap with a window. Equal overlaps
    /// preserve input order. An offscreen window selects the closest display.
    public static func index(containing windowFrame: CGRect, in displayFrames: [CGRect]) throws -> Int? {
        try validate(windowFrame)
        for frame in displayFrames { try validate(frame) }
        guard !displayFrames.isEmpty else { return nil }

        var selected = 0
        var bestArea: CGFloat = 0
        for (index, frame) in displayFrames.enumerated() {
            let overlap = windowFrame.intersection(frame)
            // Normalize by the same window dimensions to avoid area overflow.
            let area = overlap.isNull ? 0 : (overlap.width / windowFrame.width) * (overlap.height / windowFrame.height)
            if area > bestArea {
                selected = index
                bestArea = area
            }
        }
        if bestArea > 0 { return selected }

        var bestDistance = CGFloat.infinity
        for (index, frame) in displayFrames.enumerated() {
            // Distance from the window center to the closest point of each display.
            let x = min(max(windowFrame.midX, frame.minX), frame.maxX)
            let y = min(max(windowFrame.midY, frame.minY), frame.maxY)
            let distance = hypot(windowFrame.midX - x, windowFrame.midY - y)
            if distance < bestDistance {
                selected = index
                bestDistance = distance
            }
        }
        return selected
    }
}

public enum CoordinateSpace {
    /// AppKit uses a bottom-left origin; Accessibility uses a top-left origin.
    /// Supply the primary display's full frame, never its visible frame.
    public static func accessibilityFrame(fromAppKit frame: CGRect, primaryDisplayFrame: CGRect) throws -> CGRect {
        try validate(frame)
        try validate(primaryDisplayFrame)
        let converted = CGRect(x: frame.minX, y: primaryDisplayFrame.maxY - frame.maxY,
                               width: frame.width, height: frame.height)
        try validate(converted)
        return converted
    }
}
