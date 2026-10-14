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
        if arguments == ["--fixture"] {
            app.setActivationPolicy(.regular)
            delegate = FixtureDelegate()
        } else if arguments.count == 2, arguments[0] == "--controller", let processID = Int32(arguments[1]) {
            app.setActivationPolicy(.accessory)
            delegate = ControllerDelegate(processID: processID)
        } else {
            print("Usage: smoke --fixture | --controller <fixture-pid>")
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first else { exit(1) }
        let initial = CGRect(x: screen.frame.midX - 300, y: screen.frame.midY - 200, width: 600, height: 400)
        let window = NSWindow(contentRect: initial, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Synthetic window placement check"
        window.minSize = CGSize(width: 100, height: 100)
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
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
    init(processID: pid_t) { self.processID = processID }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                // Activation settling belongs to the fixture, never normal placement.
                try await Task.sleep(for: .milliseconds(300))
                let manager = WindowManager()
                let target = try await manager.captureActiveWindow(expectedProcessID: processID)
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
                try await verifyRapidThirds(manager: manager, target: target)
                try await verifyDisplayTransfers(manager: manager, target: target)
                print("PASS: all 18 zones, a queued j/k/l burst, and whole-window display transfers using only the synthetic window.")
                exit(0)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
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
                // Whole placement must span this display's available width;
                // menu bar / visible Dock may reduce its usable dimensions.
                guard result.requestedFrame.width > frames[expected].width / 2,
                      result.requestedFrame.height > frames[expected].height / 2 else { throw SmokeFailure.frameMismatch }
                current = result.actualFrame
                print("display \(direction) -> display[\(expected)]: whole verified, \(current)")
            }
        }
    }
}

private enum SmokeFailure: Error { case frameMismatch }
