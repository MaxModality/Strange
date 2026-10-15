# Strange

Strange is a native macOS window manager. Version **0.5.0** calculates display zones and moves the active window using global shortcuts and public macOS APIs. It requires macOS 13 or later and Swift 6.2 or later. A lightweight AppKit menu-bar app keeps shortcuts active without taking focus from the target window.

## Shortcuts

| Modifiers | Keys | Zones, in key order |
| --- | --- | --- |
| Control + Option | Return/Enter | Whole |
| Control + Option | `-` / `=` | Shrink / grow free edges |
| Control + Option | ← → ↑ ↓ | Left, right, top, bottom halves |
| Control + Option | `j k l` | Left, center, right thirds |
| Control + Option | `u o m .` | Top-left, top-right, bottom-left, bottom-right quadrants |
| Control + Option + Command | `u i o m , .` | Top-left, top-center, top-right, bottom-left, bottom-center, bottom-right sixths |
| Control + Option + Command | ← / → | Previous / next display, filling its whole usable area |

Display movement orders screens by their left edge, then top-to-bottom for vertically aligned screens, with system order breaking identical-position ties. It wraps at both ends. A single display keeps the window there and applies whole mode. Each move uses the window's current display (largest intersection), so two quick Right presses advance twice. Transfers first shrink dimensions that would overflow the destination, move the window to its origin, then request its whole size there; this prevents source-display size limits from leaving unused space on a taller or wider destination. The destination's own dimensions, scale, menu bar, and hidden-Dock correction determine its whole frame; landscape and portrait displays can be mixed.

Resize presses move every free side inward (`-`) or outward (`=`) by 5% of the usable display width or height, rounded to a physical pixel. Sides within one physical pixel of a usable display edge stay anchored in both directions. Growth stops at that boundary; menu bar, safe-area, and visible Dock reservations are respected. A floating window changes on all four sides, a corner window on its two free sides, and a full-height window only horizontally. A window touching all four edges stays unchanged, including on shrink. Shrinking stops at the application's accepted minimum size; application size limits are verified and anchored with the same bounded readbacks used for zone placement. Partly offscreen windows are first fitted into their selected display's usable area for the calculation. Every repeated resize press executes separately against the latest frame.

No Shift modifier is used. The comma and period keys mean `,` and `.`, not `<` and `>`. Bindings use physical ANSI key positions, so positions remain consistent when the keyboard layout changes. Return/Enter means the main Return key. The additional Command modifier selects sixths; `Control + Option + Command + J/K/L` has no binding.

The menu-bar app registers only these combinations through Carbon's hotkey API. It does not monitor typing and does not need Input Monitoring permission. If any shortcut cannot be registered, all registrations are released and the menu reports the unavailable shortcut. Resolve the conflict in the other app or macOS settings, then choose **Retry Shortcut Registration**. Registration does not take a shortcut away from another owner. Quit releases all shortcuts. Rapid distinct presses run in order: `j`, `k`, `l` performs all three moves. Only consecutive duplicate zone placements for the same app are coalesced; relative display moves and resizes always execute individually. One worker handles at most 32 pending requests; overflow reports that the new press was not accepted.

## Zone behavior

Zones resolve usable space from `NSScreen.frame`, `visibleFrame`, and `safeAreaInsets`. When the Dock auto-hides, Strange reclaims the configured Dock edge even if `visibleFrame` still reserves a full Dock-sized gap. It preserves the other visible edges, including the menu bar, and clamps to hardware-safe bounds. When the Dock remains visible, its reservation remains respected. “Whole” fills the resolved area; it does not enter macOS fullscreen mode.

Dock behavior is read using Core Foundation preferences for only `autohide` and `orientation`. These keys are macOS implementation details rather than a guaranteed AppKit contract. If the settings cannot be read or recognized, Strange conservatively uses the visible safe area. It never changes Dock settings. Metadata is sampled on every placement so a later request reflects current settings, and invalid or disjoint geometry fails instead of expanding outside a display. Apple documents that `visibleFrame` can remain smaller than the screen with Dock hiding enabled; the resolver intentionally removes that edge reservation.

| Portion | Zone names | Arrangement |
| --- | --- | --- |
| Whole | `whole` | Full usable area |
| Halves | `leftHalf`, `rightHalf`, `topHalf`, `bottomHalf` | Two columns or two rows |
| Thirds | `leftThird`, `centerThird`, `rightThird` | Three columns |
| Quadrants | `topLeftQuadrant`, `topRightQuadrant`, `bottomLeftQuadrant`, `bottomRightQuadrant` | Two columns × two rows |
| Sixths | `topLeftSixth`, `topCenterSixth`, `topRightSixth`, `bottomLeftSixth`, `bottomCenterSixth`, `bottomRightSixth` | Three columns × two rows |

Portrait displays preserve the same arrangement: thirds remain left, center, and right. Sixths remain three columns across two rows. The calculations use the display's actual dimensions without swapping width and height. All geometry uses points, with shared internal boundaries rounded to physical pixels using the display's backing scale. Neighboring cells meet exactly and the outer available bounds are preserved.

Those partitions specify the ideal size. If an app refuses to shrink that far, Strange positions the size it actually accepts using the zone's anchor: left zones grow rightward from the left edge, right zones grow leftward from the right edge, and center zones remain centered on the available display. Top and bottom zones use the corresponding vertical edge. A larger minimum-size window may overlap adjacent zones, but it stays inside the display whenever its dimensions fit. No minimum sizes are guessed or persisted; the current Accessibility readbacks determine the effective frame.

The target display is the one with the largest intersection with the active window's frame. Ties preserve screen order. A fully offscreen window uses the display nearest its center. Display frames are sampled for each request, so the next request reflects display rotation, resolution, or arrangement changes.

## Architecture

- `StrangeCore`: stateless edge-resize and zone geometry, numeric validation, hidden-Dock space resolution, display selection, and conversion from AppKit's bottom-left coordinates to Accessibility's top-left coordinates. Conversion uses the primary screen's full frame and supports displays above, below, or left of it.
- `StrangeMac`: `WindowManager` actor using Accessibility to capture the frontmost app's focused window, check that it supports moving and resizing, apply the frame, and verify the result. Screen and workspace queries run on the main actor; Accessibility traffic runs away from the main actor. `HotKeyBinding.defaults` defines 22 bindings carrying a `WindowCommand` (zone placement, display move, or edge resize), and `GlobalHotKeys` owns OS registrations. Swift 6.2's isolated deinitialization releases the handler and registrations on the main actor if the owner is dropped. Concurrent placement requests return `busy` rather than accumulate.
- `strange`: small command-line harness for explicit placement and permission requests.
- `strange-app`: AppKit menu-bar executable with a shortcut reference, Accessibility permission action, registration retry, placement status, and Quit. `PlacementQueue` serializes requests and retains one opaque `WindowTarget` per burst. Pending moves stop if that window or its app loses focus, rather than replaying against a different window. Its fixed-size status item appears immediately; permission and placement work do not create or resize a loading window.

Each AX element uses a 250 ms messaging timeout. Transient `cannotComplete` failures receive up to three attempts with 50 ms and 100 ms backoff. Other errors fail immediately. Placement reads the size after resizing and anchors the accepted dimensions before setting position. AppKit can report intermediate sizes while a resize is in flight; a mismatch receives at most 16 ms then 32 ms polling to distinguish a settling animation from a stable accepted minimum. An immediate match has no settling wait. Stable minimum sizes at least as large as the ideal are accepted and anchored; a smaller source-display clamp during a display transfer still requires correction on the destination. Position/size corrections remain bounded to three passes, and every setter attempt rechecks focus. `PlacementResult.idealFrame` preserves the ideal zone or resize frame, `requestedFrame` is the effective anchored frame, and `isSizeConstrained` reports an app-constrained fit. Success verifies the effective frame within one physical pixel. Unresponsive applications can take longer.

Accessibility has separate position and size setters, so placement is not atomic. Cancellation, focus changes, or application failures after one setter can leave a partially changed frame. The manager stops further writes and reports the error. It does not force another app to the foreground or automatically restore a frame after focus has changed. macOS also offers no atomic focus-check-and-write operation; a switch during an in-flight system call remains possible.

Minimized and fullscreen windows, windows with read-only position or size, and apps lacking a focused AX window fail without intentionally changing their state. Minimum sizes larger than a zone use the anchored fit and the menu reports placement at the supported size. If a minimum exceeds the entire usable display, Strange retains the requested side/center alignment but returns `windowLargerThanDisplay`; no position can make all of that window visible. Apps that reject the effective position or cannot settle after bounded attempts return `frameNotAccepted`.

## Bootstrap

Install Xcode or compatible Swift tools, then run from this directory:

```sh
swift build
swift test
swift run strange --version
swift run strange
```

Start the menu-bar app and leave it running:

```sh
swift run strange-app
```

To build a local app bundle with a Finder/application icon:

```sh
bash Scripts/build-app.sh
open .build/Strange.app
```

The script builds the optimized executable, renders every standard ICNS size from the same vector used at runtime, writes the bundle metadata, and ad-hoc signs `.build/Strange.app` for local use. Quit any running Strange instance before launching the bundle. Grant Accessibility access to this app if macOS asks. The bundle is a local development build; distribution signing and notarization are separate release steps.

The menu-bar and application icons share a circle divided into nine sections by two vertical and two horizontal straight lines. The menu-bar image is an 18-point template that macOS tints for the current appearance. The app icon has a dark circular fill with light strokes and transparency outside the circle. `Sources/StrangeApp/StrangeIcon.swift` is the canonical vector source. Generated previews and the iconset are under `.build/icons`, and the Finder icon is stored inside the app bundle. No images or drawing callbacks capture application state.

Click the Strange icon in the menu bar and choose **Enable Accessibility Access…**, grant permission in System Settings, and return to the window you want to position. Press any registered shortcut. The menu shows permission, registration, and placement status without displaying application names or window content. Quit through the menu when finished. Launch one instance at a time; a second instance will report shortcut registration conflicts.

For a short registration smoke check that releases every shortcut immediately:

```sh
swift run strange-app --check-shortcuts
```

Request Accessibility access explicitly:

```sh
swift run strange --request-permission
```

Enable the executable or its launching application as macOS identifies it in **System Settings → Privacy & Security → Accessibility**, then rerun. Rebuilt unsigned command-line executables may require renewed permission. A stable signed app bundle will be needed for distribution.

To try placement, arrange for the intended window to be frontmost when the command starts. Running a command from Terminal normally targets Terminal's focused window. For a different app, use a short shell delay and switch to that app:

```sh
sleep 3 && swift run strange move leftThird
```

Library integration for a hotkey callback:

```swift
import StrangeCore
import StrangeMac

let manager = WindowManager() // Retain one instance.
let result = try await manager.moveActiveWindow(to: .leftThird)
// result.requestedFrame and result.actualFrame are in AX coordinates.
```

Geometry can also be used independently:

```swift
import CoreGraphics
import StrangeCore

let available = CGRect(x: 0, y: 24, width: 1080, height: 1856)
let frame = try ZoneGeometry.frame(for: .centerThird, in: available, scale: 2)
```

## Verification and privacy

Automated tests cover free-edge resizing, boundary clamping, anchored resize constraints, repeated resize ordering, minimum-size anchors across all zone families, portrait containment, oversized dimensions, replayed intermediate/stable resize readbacks, no-wait immediate matches, bounded settlement and cancellation, ordered rapid thirds, duplicate coalescing, queue bounds, cancellation/restart, focus and permission changes, worker deallocation, hidden bottom/side Dock gaps, menu-bar/notch preservation, exact shortcut mapping, unique combinations, modifier separation, unshifted punctuation, landscape and portrait layouts, arbitrary ratios, negative and fractional coordinates, pixel boundary agreement, full partition coverage, invalid numeric input, multiple display selection, coordinate conversion, bounded transient retries, immediate permanent failures, and frame verification. They do not establish compatibility with every application's Accessibility implementation.

`Tests/Manual/NativePlacementSmoke.swift` is an optional two-process GUI fixture for real Accessibility verification. Its controller checks all 18 zones, an immediately queued `j/k/l` burst, and whole-mode transfers in both directions through all connected displays, targeting only its companion process's synthetic window. Use separate processes: Accessibility setters targeting an AppKit window in the caller's own process can execute AppKit off the main thread, so `WindowManager` explicitly rejects its own process. The fixture auto-closes after 15 seconds or `SIGUSR1`, and restores the previous app only if the fixture still owns focus. It prints synthetic geometry, fixture process identifiers, and timings.

The `--fixture-constrained` and `--controller-constrained <fixture-pid>` variants exercise a native portrait window whose minimum width and height exceed the requested cells. The controller checks all 17 partial zones for containment and side/center alignment. This check requires that the synthetic window actually owns foreground focus; it stops instead of moving another application if macOS does not activate the fixture. Fixture diagnostics contain only synthetic geometry and process identifiers, never window content.

For manual validation, grant Accessibility access and try whole, thirds, quadrants, and sixths in a resizable native window; repeat on a portrait display and a secondary display positioned left of or above the primary one. Check that the Dock/menu bar remain outside the requested area. Try a window with a minimum width, fullscreen mode, and switching focus during placement to confirm failures are reported.

The implementation requests only Accessibility access. It reads process identifiers and window geometry temporarily, without reading window titles or document content. It has no network calls, telemetry, persistent window cache, or credentials. AX and CF resources are ARC-managed locals; operations and retry tasks are bounded, and the actor releases its busy state with `defer` on every exit. Hotkey registrations are released on failure, explicit stop, owner deinitialization, and app termination. The app cancels its queue worker at shutdown; queue and hotkey callbacks use weak ownership to avoid retain cycles. The burst target is released when the queue drains or cancels. A regression test verifies queue deallocation while an operation is suspended. Runtime Instruments leak profiling against a signed application remains a release check.

`VERSION` records the semantic version; 0.5.0 adds anchored free-edge shrink/grow shortcuts. Version 0.4.3 fixed display-transfer ordering so resizing happens on the destination screen, using its corrected available space. Version 0.4.2 added minimum-size anchors and bounded resize settlement. New features and breaking API changes before 1.0 increment the minor version; compatible fixes increment the patch version. Keep both executable versions in sync with `VERSION`.

API references: [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe), [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement), and [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout).
