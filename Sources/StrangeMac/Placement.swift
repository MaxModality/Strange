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

/// Establish the destination screen before requesting its size. Otherwise the
/// source screen can clamp a tall portrait frame or a wide landscape frame.
enum DisplayTransfer {
    static func prepare(source: CGRect, destination: CGRect, tolerance: CGFloat,
                        isolation: isolated (any Actor)? = #isolation,
                        move: (CGPoint) async throws -> Void,
                        resize: (CGSize) async throws -> Void,
                        readFrame: () async throws -> CGRect,
                        wait: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws -> CGRect {
        try Task.checkCancellation()
        // A very wide source window can still belong mostly to the source
        // after moving its origin onto a skinny neighboring screen. Shrink
        // overflowing dimensions first so relocation establishes screen ownership.
        let transitSize = CGSize(width: min(source.width, destination.width),
                                 height: min(source.height, destination.height))
        if transitSize != source.size {
            try await resize(transitSize)
            _ = try await SizeSettlement.read(requested: transitSize, tolerance: tolerance,
                                              isolation: isolation, readFrame: readFrame, wait: wait)
        }
        try Task.checkCancellation()
        try await move(destination.origin)
        try Task.checkCancellation()
        // Always resize after relocation, even if the original size matched:
        // moving between screens can itself adjust the window's dimensions.
        try await resize(destination.size)
        return try await SizeSettlement.read(requested: destination.size, tolerance: tolerance,
                                             isolation: isolation, readFrame: readFrame, wait: wait).frame
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
