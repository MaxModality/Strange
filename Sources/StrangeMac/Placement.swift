import Foundation
import CoreGraphics

public enum PlacementError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case noActiveWindow
    case noDisplay
    case unsupportedWindow
    case focusChanged
    case busy
    case accessibility(Int32)
    case frameNotAccepted
}

/// Short, bounded backoff only for transient Accessibility transport failures.
enum AccessibilityRetry {
    static func call<T: Sendable>(isolation: isolated (any Actor)? = #isolation, _ operation: () async throws -> T) async throws -> T {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do { return try await operation() }
            catch PlacementError.accessibility(let code) where code == -25204 && attempt < 2 {
                try await Task.sleep(for: .milliseconds(50 * (1 << attempt)))
            }
        }
        throw PlacementError.frameNotAccepted
    }
}

/// A placement can succeed only after the target application reports the requested frame.
enum FrameVerification {
    static func matches(_ actual: CGRect, _ requested: CGRect, tolerance: CGFloat) -> Bool {
        [actual.origin.x, actual.origin.y, actual.size.width, actual.size.height].allSatisfy(\.isFinite)
        && actual.size.width > 0 && actual.size.height > 0
        && abs(actual.minX - requested.minX) <= tolerance
        && abs(actual.minY - requested.minY) <= tolerance
        && abs(actual.width - requested.width) <= tolerance
        && abs(actual.height - requested.height) <= tolerance
    }
}
