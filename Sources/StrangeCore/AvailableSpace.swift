import Foundation
import CoreGraphics

/// The Dock's edge in AppKit's bottom-left coordinate system.
public enum DockEdge: Sendable {
    case bottom, left, right
}

public enum AvailableSpace {
    /// Resolve usable space from current display metadata. When the Dock hides,
    /// reclaim its edge even if visibleFrame still reserves an obsolete Dock inset.
    /// Other visible bounds, especially the menu bar, remain respected. safeFrame
    /// supplies hardware-safe bounds (for example, below a display notch).
    public static func frame(displayFrame: CGRect, visibleFrame: CGRect,
                             safeFrame: CGRect, dockAutoHides: Bool,
                             dockEdge: DockEdge) throws -> CGRect {
        try validate(displayFrame)
        try validate(visibleFrame)
        try validate(safeFrame)

        let safe = safeFrame.intersection(displayFrame)
        let visible = visibleFrame.intersection(safe)
        // Fail closed on inconsistent metadata instead of expanding an offscreen
        // or disjoint rectangle into a target on an unrelated display.
        try validate(safe)
        try validate(visible)
        guard dockAutoHides else { return visible }

        let resolved: CGRect
        switch dockEdge {
        case .bottom:
            resolved = CGRect(x: visible.minX, y: safe.minY,
                              width: visible.width, height: visible.maxY - safe.minY)
        case .left:
            resolved = CGRect(x: safe.minX, y: visible.minY,
                              width: visible.maxX - safe.minX, height: visible.height)
        case .right:
            resolved = CGRect(x: visible.minX, y: visible.minY,
                              width: safe.maxX - visible.minX, height: visible.height)
        }
        try validate(resolved)
        return resolved
    }
}
