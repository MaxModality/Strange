// Two-process GUI integration check: Accessibility must address a separate app.
// Only the fixture's synthetic window is eligible; working windows are never used.
import AppKit
import Foundation
import StrangeCore
import StrangeMac

@main @MainActor struct NativePlacementSmoke {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let app = NSApplication.shared
        let delegate: NSObject & NSApplicationDelegate
        if arguments == ["--fixture"] || arguments == ["--fixture-constrained"] {
            app.setActivationPolicy(.regular)
            delegate = FixtureDelegate(constrained: arguments == ["--fixture-constrained"])
        } else if arguments.count == 2, ["--controller", "--controller-constrained"].contains(arguments[0]), let processID = Int32(arguments[1]) {
            app.setActivationPolicy(.prohibited)
            delegate = ControllerDelegate(processID: processID, constrained: arguments[0] == "--controller-constrained")
        } else {
            print("Usage: smoke --fixture[-constrained] | --controller[-constrained] <fixture-pid>")
            exit(64)
        }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let previousApp = NSWorkspace.shared.frontmostApplication
    private var quitSignal: DispatchSourceSignal?
    private var timeout: Timer?
    private let constrained: Bool
    init(constrained: Bool) { self.constrained = constrained }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = constrained ? NSScreen.screens.first { $0.frame.height > $0.frame.width } : NSScreen.screens.first
        guard let screen else { exit(1) }
        let minimum = constrained
            ? CGSize(width: floor(screen.visibleFrame.width * 3 / 4), height: floor(screen.visibleFrame.height * 2 / 3))
            : CGSize(width: 100, height: 100)
        let size = constrained ? minimum : CGSize(width: 600, height: 400)
        let initial = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                             width: size.width, height: size.height)
        let window = NSWindow(contentRect: initial, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Synthetic window placement check"
        window.minSize = minimum
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        if constrained { window.setFrame(initial, display: true) }
        print("synthetic fixture frame: \(window.frame), minimum: \(window.minSize)")
        print("fixture process ID: \(getpid())")
        fflush(stdout)
        NSApplication.shared.activate(ignoringOtherApps: true)
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.finish() }
        }
        quitSignal = source
        source.resume()
        timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    private func finish() {
        timeout?.invalidate()
        quitSignal?.cancel()
        let ownsFocus = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        window?.orderOut(nil)
        if ownsFocus { _ = previousApp?.activate(options: []) }
        exit(0)
    }
}

@MainActor private final class ControllerDelegate: NSObject, NSApplicationDelegate {
    private let processID: pid_t
    private var queue: PlacementQueue?
    private let constrained: Bool
    init(processID: pid_t, constrained: Bool) {
        self.processID = processID
        self.constrained = constrained
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                // Activation settling belongs to the fixture, never normal placement.
                for _ in 0..<20 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == processID { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                let manager = WindowManager()
                let target = try await manager.captureActiveWindow(expectedProcessID: processID)
                if constrained {
                    try await verifyConstrainedPlacement(manager: manager, target: target)
                    print("PASS: minimum-size portrait placements stay visible and honor their anchors.")
                    exit(0)
                }
                for zone in WindowZone.allCases {
                    let start = ContinuousClock.now
                    let result = try await manager.moveWindow(target, to: zone)
                    let actual = result.actualFrame
                    let requested = result.requestedFrame
                    let tolerance = 1 / (NSScreen.screens.first?.backingScaleFactor ?? 1)
                    guard abs(actual.minX - requested.minX) <= tolerance,
                          abs(actual.minY - requested.minY) <= tolerance,
                          abs(actual.width - requested.width) <= tolerance,
                          abs(actual.height - requested.height) <= tolerance else { throw SmokeFailure.frameMismatch }
                    print("\(zone.rawValue): \(result.actualFrame), verified in \(start.duration(to: .now))")
                }
                try await verifyQuadrantReset(manager: manager, target: target)
                try await verifyRapidThirds(manager: manager, target: target)
                try await verifyDisplayTransfers(manager: manager, target: target)
                print("PASS: all 20 zones, quadrant resets after shrinking, a queued j/k/l burst, and whole-window display transfers using only the synthetic window.")
                exit(0)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
    }

    private func verifyQuadrantReset(manager: WindowManager, target: WindowTarget) async throws {
        for zone: WindowZone in [.topLeftQuadrant, .topRightQuadrant, .bottomLeftQuadrant, .bottomRightQuadrant] {
            let initial = try await manager.moveWindow(target, to: zone)
            let grown = try await manager.performWindowCommand(target, command: .resize(.grow))
            guard grown.actualFrame.width > initial.actualFrame.width + 1,
                  grown.actualFrame.height > initial.actualFrame.height + 1 else { throw SmokeFailure.frameMismatch }
            _ = try await manager.moveWindow(target, to: zone)
            var shrunken = initial.actualFrame
            for _ in 0..<2 {
                shrunken = try await manager.performWindowCommand(target, command: .resize(.shrink)).actualFrame
            }
            guard shrunken.width < initial.actualFrame.width - 1,
                  shrunken.height < initial.actualFrame.height - 1 else { throw SmokeFailure.frameMismatch }
            let regrown = try await manager.performWindowCommand(target, command: .resize(.grow))
            guard regrown.actualFrame.width > shrunken.width + 1,
                  regrown.actualFrame.height > shrunken.height + 1 else { throw SmokeFailure.frameMismatch }
            let restored = try await manager.moveWindow(target, to: zone)
            let actual = restored.actualFrame
            let expected = initial.idealFrame
            guard abs(actual.minX - expected.minX) <= 1, abs(actual.minY - expected.minY) <= 1,
                  abs(actual.width - expected.width) <= 1, abs(actual.height - expected.height) <= 1 else {
                throw SmokeFailure.frameMismatch
            }
            print("quadrant reset \(zone.rawValue): grow, shrink, regrow, and reset verified")
        }
    }

    private func verifyRapidThirds(manager: WindowManager, target: WindowTarget) async throws {
        let expected: [WindowZone] = [.leftThird, .centerThird, .rightThird]
        var completed: [WindowZone] = []
        var finished = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue = PlacementQueue(operation: { zone, processID in
                guard processID == target.processID else { throw PlacementError.focusChanged }
                let start = ContinuousClock.now
                _ = try await manager.moveWindow(target, to: zone)
                print("queued \(zone.rawValue): verified in \(start.duration(to: .now))")
            }, onSuccess: { zone in
                completed.append(zone)
                guard completed.count == expected.count, !finished else { return }
                finished = true
                if completed == expected { continuation.resume() }
                else { continuation.resume(throwing: SmokeFailure.frameMismatch) }
            }, onFailure: { error in
                guard !finished else { return }
                finished = true
                continuation.resume(throwing: error)
            })
            for zone in expected { queue?.enqueue(zone: zone, processID: target.processID) }
        }
        queue?.cancel()
        queue = nil
    }

    private func verifyDisplayTransfers(manager: WindowManager, target: WindowTarget) async throws {
        guard let primary = NSScreen.screens.first else { throw PlacementError.noDisplay }
        let frames = try NSScreen.screens.map {
            try CoordinateSpace.accessibilityFrame(fromAppKit: $0.frame, primaryDisplayFrame: primary.frame)
        }
        var current = try await manager.moveWindow(target, to: .whole).actualFrame
        for direction in [DisplayDirection.right, .left] {
            for _ in frames.indices {
                guard let source = try DisplayGeometry.index(containing: current, in: frames),
                      let expected = try DisplayNavigation.destinationIndex(from: source, direction: direction, in: frames) else {
                    throw PlacementError.noDisplay
                }
                let result = try await manager.performWindowCommand(target, command: .moveDisplay(direction))
                let actualIndex = try DisplayGeometry.index(containing: result.actualFrame, in: frames)
                guard actualIndex == expected else { throw SmokeFailure.frameMismatch }
                // Verify the full corrected destination frame on the first
                // transfer command, not merely that it reached the right screen.
                let ideal = result.idealFrame
                let tolerance = 1 / NSScreen.screens[expected].backingScaleFactor
                guard abs(result.actualFrame.minX - ideal.minX) <= tolerance,
                      abs(result.actualFrame.minY - ideal.minY) <= tolerance,
                      abs(result.actualFrame.width - ideal.width) <= tolerance,
                      abs(result.actualFrame.height - ideal.height) <= tolerance else { throw SmokeFailure.frameMismatch }
                current = result.actualFrame
                print("display \(direction) -> display[\(expected)]: whole verified, \(current)")
            }
        }
    }

    private func verifyConstrainedPlacement(manager: WindowManager, target: WindowTarget) async throws {
        print("checking constrained whole placement")
        let whole = try await manager.moveWindow(target, to: .whole)
        let available = whole.idealFrame
        guard let primary = NSScreen.screens.first else { throw PlacementError.noDisplay }
        let screens = NSScreen.screens
        let frames = try screens.map {
            try CoordinateSpace.accessibilityFrame(fromAppKit: $0.frame, primaryDisplayFrame: primary.frame)
        }
        guard let index = try DisplayGeometry.index(containing: available, in: frames) else { throw PlacementError.noDisplay }
        let tolerance = 1 / screens[index].backingScaleFactor
        for zone in WindowZone.allCases where zone != .whole {
            print("checking constrained \(zone.rawValue)")
            let result = try await manager.moveWindow(target, to: zone)
            let actual = result.actualFrame
            guard result.isSizeConstrained, available.insetBy(dx: -tolerance, dy: -tolerance).contains(actual) else {
                throw SmokeFailure.frameMismatch
            }
            switch zone {
            case .leftHalf, .leftThird, .leftTwoThirds, .topLeftQuadrant, .bottomLeftQuadrant, .topLeftSixth, .bottomLeftSixth:
                guard abs(actual.minX - available.minX) <= tolerance else { throw SmokeFailure.frameMismatch }
            case .rightHalf, .rightThird, .rightTwoThirds, .topRightQuadrant, .bottomRightQuadrant, .topRightSixth, .bottomRightSixth:
                guard abs(actual.maxX - available.maxX) <= tolerance else { throw SmokeFailure.frameMismatch }
            default:
                guard abs(actual.midX - available.midX) <= tolerance else { throw SmokeFailure.frameMismatch }
            }
            switch zone {
            case .topHalf, .topLeftQuadrant, .topRightQuadrant, .topLeftSixth, .topCenterSixth, .topRightSixth:
                guard abs(actual.minY - available.minY) <= tolerance else { throw SmokeFailure.frameMismatch }
            case .bottomHalf, .bottomLeftQuadrant, .bottomRightQuadrant, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
                guard abs(actual.maxY - available.maxY) <= tolerance else { throw SmokeFailure.frameMismatch }
            default:
                guard abs(actual.midY - available.midY) <= tolerance else { throw SmokeFailure.frameMismatch }
            }
            print("constrained \(zone.rawValue): visible and anchored, \(actual)")
        }
    }
}

private enum SmokeFailure: Error { case frameMismatch }
