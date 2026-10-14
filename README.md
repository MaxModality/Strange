# Strange

Strange is a native macOS window-manager foundation. Version **0.3.0** adds global shortcut registration and ordered placement commands. It requires macOS 13 or later and Swift 6.2 or later.

## Purpose and architecture

- `StrangeCore` calculates whole, halves, left/center/right thirds, quadrants, and three-column/two-row sixths on every display orientation. It validates numeric input, shares pixel boundaries, resolves hidden-Dock space, converts coordinates, and selects/orders displays.
- `StrangeMac` captures an opaque window target, checks focus before every write, and uses bounded Accessibility timeouts and transient backoff. Successful placement is verified immediately; only mismatched frames receive short settling delays. It rejects its own process to avoid in-process AppKit calls from a worker actor.
- `strange` provides explicit placement, version output, and an Accessibility permission action. `HotKeyBinding` defines 20 combinations, `GlobalHotKeys` owns OS registrations, and `PlacementQueue` serializes commands. A native menu-bar runner is the next layer.

Placement uses each display's current frame, visible frame, and safe-area insets. Only recognized hidden-Dock settings reclaim that edge; unreadable settings retain the visible safe area. No Dock settings are changed. A retained target lets later commands stop if focus changes. `moveActiveWindowToDisplay` selects the previous/next display, wraps at either end, and fills its whole usable area.

## Bootstrap

```sh
swift build
swift test
swift run strange --version
swift run strange --request-permission
swift run strange move leftThird
```

Grant Accessibility access in System Settings. CLI placement targets the currently active window, usually Terminal when invoked there. For another app, use a short shell delay and switch to it before execution.

## Reliability and privacy

AX position and size are separate writes; cancellation or focus changes may leave a partial placement. Minimum-size constraints can cause `frameNotAccepted`. Fullscreen, minimized, and unsupported windows are rejected. Calls have 250 ms messaging timeouts, transient failures have at most three attempts, and correction has at most three passes. ARC owns temporary AX handles. No window titles or document contents are read, and there is no network, telemetry, persistent window cache, or credentials.

`VERSION` records the semantic version. New features before 1.0 increment the minor version; compatible fixes increment the patch version.

## Shortcut and queue integration

Control+Option: Return fills whole, arrows select halves, J/K/L select thirds, U/O/M/period select quadrants. Control+Option+Command: U/I/O/M/comma/period select sixths; Left/Right move to the previous/next display and fill whole. Keys use physical ANSI positions without Shift.

Global hotkeys use Carbon registration with an AppKit event loop, rather than monitoring arbitrary typing. Registration is all-or-nothing and failures release partial registrations. Main-actor stop/deinitialization releases handlers. No Input Monitoring permission is requested.

The queue keeps distinct commands in order, coalesces only consecutive duplicate zone placements, and never coalesces relative display moves. One worker holds at most 32 pending commands; overflow is reported. Focus/permission failures clear pending work. Cancellation generations prevent stale callbacks. Weak worker ownership allows queue deallocation during suspended operations, covered by a regression test.
