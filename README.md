# Strange

Strange is a native macOS window-manager foundation. Version **0.2.0** adds Accessibility placement and a CLI to the geometry library. It requires macOS 13 or later and Swift 6.2 or later.

## Purpose and architecture

- `StrangeCore` calculates whole, halves, left/center/right thirds, quadrants, and three-column/two-row sixths on every display orientation. It validates numeric input, shares pixel boundaries, resolves hidden-Dock space, converts coordinates, and selects/orders displays.
- `StrangeMac` captures an opaque window target, checks focus before every write, and uses bounded Accessibility timeouts and transient backoff. Successful placement is verified immediately; only mismatched frames receive short settling delays. It rejects its own process to avoid in-process AppKit calls from a worker actor.
- `strange` provides explicit placement, version output, and an Accessibility permission action. Hotkeys and the application are the next layer.

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
