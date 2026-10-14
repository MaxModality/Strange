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
    case windowLargerThanDisplay
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

/// Distinguish an in-flight resize from the size the app actually accepts.
/// Poll only a mismatch, with bounded waits; never pause an immediate match.
enum SizeSettlement {
    static func read(requested: CGSize, tolerance: CGFloat, isolation: isolated (any Actor)? = #isolation,
                     readFrame: () async throws -> CGRect,
                     wait: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws -> (frame: CGRect, isStable: Bool) {
        try Task.checkCancellation()
        var previous = try await readFrame()
        for milliseconds in [16, 32] {
            if matches(previous.size, requested, tolerance: tolerance) { return (previous, true) }
            try await wait(.milliseconds(milliseconds))
            try Task.checkCancellation()
            let next = try await readFrame()
            if matches(next.size, previous.size, tolerance: tolerance) { return (next, true) }
            previous = next
        }
        return (previous, matches(previous.size, requested, tolerance: tolerance))
    }

    private static func matches(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat) -> Bool {
        lhs.width.isFinite && lhs.height.isFinite && lhs.width > 0 && lhs.height > 0
        && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
