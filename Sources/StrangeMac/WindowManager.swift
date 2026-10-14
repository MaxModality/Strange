import AppKit
import ApplicationServices
import StrangeCore

// AXUIElement is a retained, immutable CF handle. Handles never escape this file;
// all calls using them are serialized by WindowManager. Sendability permits
// passing the handle through bounded retry closures without transferring ownership.
private struct AXHandle: @unchecked Sendable {
    let raw: AXUIElement
}

/// An opaque focus identity reused by an ordered burst of hotkeys. It never
/// exposes titles or contents, and is revalidated before every window write.
public struct WindowTarget: Sendable {
    fileprivate let application: AXHandle
    fileprivate let window: AXHandle
    public let processID: pid_t
}

private struct DockConfiguration: Sendable {
    let autoHides: Bool
    let edge: DockEdge

    static func read() -> Self {
        // Read only these settings; never load or persist the complete domain.
        // Preference keys are macOS implementation details: fail conservatively
        // to visibleFrame if their values cannot be read or recognized.
        let domain = "com.apple.dock" as CFString
        _ = CFPreferencesAppSynchronize(domain)
        var valid = DarwinBoolean(false)
        let autoHides = CFPreferencesGetAppBooleanValue("autohide" as CFString, domain, &valid)
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String
        let edge: DockEdge?
        switch orientation {
        case "bottom": edge = .bottom
        case "left": edge = .left
        case "right": edge = .right
        default: edge = nil
        }
        return Self(autoHides: valid.boolValue && autoHides && edge != nil, edge: edge ?? .bottom)
    }
}

public struct PlacementResult: Sendable {
    public let requestedFrame: CGRect
    public let actualFrame: CGRect
}

private struct DisplaySnapshot: Sendable {
    let frame: CGRect
    let availableFrame: CGRect
    let scale: CGFloat
}

private struct DesktopSnapshot: Sendable {
    let processID: pid_t
    let displays: [DisplaySnapshot]

    @MainActor static func capture(dock: DockConfiguration) throws -> Self {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw PlacementError.noActiveWindow
        }
        let screens = NSScreen.screens
        guard let primary = screens.first else { throw PlacementError.noDisplay }
        return try Self(processID: application.processIdentifier, displays: screens.map {
            let insets = $0.safeAreaInsets
            let safe = CGRect(x: $0.frame.minX + insets.left, y: $0.frame.minY + insets.bottom,
                              width: $0.frame.width - insets.left - insets.right,
                              height: $0.frame.height - insets.top - insets.bottom)
            let available = try AvailableSpace.frame(displayFrame: $0.frame, visibleFrame: $0.visibleFrame,
                                                    safeFrame: safe, dockAutoHides: dock.autoHides, dockEdge: dock.edge)
            return try DisplaySnapshot(
                frame: CoordinateSpace.accessibilityFrame(fromAppKit: $0.frame, primaryDisplayFrame: primary.frame),
                availableFrame: CoordinateSpace.accessibilityFrame(fromAppKit: available, primaryDisplayFrame: primary.frame),
                scale: $0.backingScaleFactor
            )
        })
    }
}

/// Retain one instance for future hotkey handlers. AX traffic runs on this actor,
/// away from the main actor; overlapping requests fail instead of building a queue.
public actor WindowManager {
    private var isPlacing = false

    public init() {}

    @MainActor public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Call only in response to a user's explicit permission action.
    @MainActor public static func requestAccessibilityPermission() -> Bool {
        // The C global is imported as non-Sendable by Swift 6. Its documented
        // constant value avoids importing shared mutable state into MainActor.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func moveActiveWindow(to zone: WindowZone) async throws -> PlacementResult {
        let target = try await captureActiveWindow()
        return try await moveWindow(target, to: zone)
    }

    public func moveActiveWindowToDisplay(_ direction: DisplayDirection) async throws -> PlacementResult {
        let target = try await captureActiveWindow()
        return try await performWindowCommand(target, command: .moveDisplay(direction))
    }

    public func captureActiveWindow(expectedProcessID: pid_t? = nil) async throws -> WindowTarget {
        guard AXIsProcessTrusted() else { throw PlacementError.accessibilityPermissionRequired }
        let processID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard let processID else { throw PlacementError.noActiveWindow }
        if let expectedProcessID, expectedProcessID != processID { throw PlacementError.focusChanged }
        // In-process AX setters may directly invoke AppKit on this worker actor.
        // A window manager must only address other applications' windows.
        guard processID != getpid() else { throw PlacementError.unsupportedWindow }
        let application = AXHandle(raw: AXUIElementCreateApplication(processID))
        try check(AXUIElementSetMessagingTimeout(application.raw, 0.25))
        let window = try await AccessibilityRetry.call(isolation: self) { try self.focusedWindow(application) }
        try check(AXUIElementSetMessagingTimeout(window.raw, 0.25))
        try await AccessibilityRetry.call(isolation: self) { try self.validate(window) }
        return WindowTarget(application: application, window: window, processID: processID)
    }

    public func moveWindow(_ focus: WindowTarget, to zone: WindowZone) async throws -> PlacementResult {
        try await performWindowCommand(focus, command: .zone(zone))
    }

    public func performWindowCommand(_ focus: WindowTarget, command: WindowCommand) async throws -> PlacementResult {
        guard !isPlacing else { throw PlacementError.busy }
        isPlacing = true
        defer { isPlacing = false }
        guard AXIsProcessTrusted() else { throw PlacementError.accessibilityPermissionRequired }
        let dock = DockConfiguration.read()
        let desktop = try await DesktopSnapshot.capture(dock: dock)
        guard desktop.processID == focus.processID else { throw PlacementError.focusChanged }
        let application = focus.application
        let window = focus.window
        try await AccessibilityRetry.call(isolation: self) { try self.validate(window) }
        let original = try await AccessibilityRetry.call(isolation: self) { try self.frame(window) }
        let frames = desktop.displays.map(\.frame)
        guard let sourceIndex = try DisplayGeometry.index(containing: original, in: frames) else {
            throw PlacementError.noDisplay
        }
        let index: Int
        let zone: WindowZone
        switch command {
        case .zone(let requestedZone):
            index = sourceIndex
            zone = requestedZone
        case .moveDisplay(let direction):
            guard let destination = try DisplayNavigation.destinationIndex(from: sourceIndex, direction: direction, in: frames) else {
                throw PlacementError.noDisplay
            }
            index = destination
            zone = .whole
        }
        let display = desktop.displays[index]
        let target = try ZoneGeometry.frame(for: zone, in: display.availableFrame, scale: display.scale)
        let tolerance = 1 / display.scale

        // AX has no atomic frame setter. Reapply size/position to accommodate apps
        // that clamp the initial position using the old window size.
        var current = original
        for attempt in 0..<3 {
            try Task.checkCancellation()
            if abs(current.width - target.width) > tolerance || abs(current.height - target.height) > tolerance {
                try await AccessibilityRetry.call(isolation: self) {
                    try await self.ensureFocus(application, window: window, processID: desktop.processID)
                    try Task.checkCancellation()
                    try self.set(window, attribute: kAXSizeAttribute, size: target.size)
                }
            }
            try await AccessibilityRetry.call(isolation: self) {
                try await self.ensureFocus(application, window: window, processID: desktop.processID)
                try Task.checkCancellation()
                try self.set(window, attribute: kAXPositionAttribute, point: target.origin)
            }
            let actual = try await AccessibilityRetry.call(isolation: self) { try self.frame(window) }
            current = actual
            if FrameVerification.matches(actual, target, tolerance: tolerance) {
                return PlacementResult(requestedFrame: target, actualFrame: actual)
            }
            if attempt < 2 {
                // No sleep on a successful normal placement. Only an observed
                // mismatch gets a short settling opportunity before correction.
                try await Task.sleep(for: .milliseconds(16 * (1 << attempt)))
            }
        }
        throw PlacementError.frameNotAccepted
    }

    private func ensureFocus(_ application: AXHandle, window: AXHandle, processID: pid_t) async throws {
        let currentPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard currentPID == processID else { throw PlacementError.focusChanged }
        // No backoff or suspension between this focused-window check and its setter.
        let currentWindow = try focusedWindow(application)
        guard CFEqual(window.raw, currentWindow.raw) else { throw PlacementError.focusChanged }
    }

    private func check(_ error: AXError) throws {
        guard error == .success else { throw PlacementError.accessibility(error.rawValue) }
    }

    private func attribute(_ element: AXHandle, _ name: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element.raw, name as CFString, &value))
        guard let value else { throw PlacementError.unsupportedWindow }
        return value
    }

    private func focusedWindow(_ application: AXHandle) throws -> AXHandle {
        let value = try attribute(application, kAXFocusedWindowAttribute)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw PlacementError.noActiveWindow }
        return AXHandle(raw: unsafeDowncast(value, to: AXUIElement.self))
    }

    private func validate(_ window: AXHandle) throws {
        guard (try attribute(window, kAXRoleAttribute)) as? String == kAXWindowRole else {
            throw PlacementError.unsupportedWindow
        }
        for name in [kAXMinimizedAttribute, "AXFullScreen"] {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(window.raw, name as CFString, &value)
            if error == .attributeUnsupported { continue }
            try check(error)
            guard let number = value as? NSNumber else { throw PlacementError.unsupportedWindow }
            guard !number.boolValue else { throw PlacementError.unsupportedWindow }
        }
        for name in [kAXPositionAttribute, kAXSizeAttribute] {
            var settable = DarwinBoolean(false)
            try check(AXUIElementIsAttributeSettable(window.raw, name as CFString, &settable))
            guard settable.boolValue else { throw PlacementError.unsupportedWindow }
        }
    }

    private func frame(_ window: AXHandle) throws -> CGRect {
        let position = try attribute(window, kAXPositionAttribute)
        let size = try attribute(window, kAXSizeAttribute)
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw PlacementError.unsupportedWindow
        }
        let positionValue = unsafeDowncast(position, to: AXValue.self)
        let sizeValue = unsafeDowncast(size, to: AXValue.self)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions) else {
            throw PlacementError.unsupportedWindow
        }
        return CGRect(origin: point, size: dimensions)
    }

    private func set(_ window: AXHandle, attribute: String, point: CGPoint) throws {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { throw PlacementError.unsupportedWindow }
        try check(AXUIElementSetAttributeValue(window.raw, attribute as CFString, value))
    }

    private func set(_ window: AXHandle, attribute: String, size: CGSize) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw PlacementError.unsupportedWindow }
        try check(AXUIElementSetAttributeValue(window.raw, attribute as CFString, value))
    }
}
