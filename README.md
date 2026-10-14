# Strange

Strange is a native macOS window-manager foundation. Version **0.1.0** provides a stateless Swift geometry library. It requires macOS 13 or later and Swift 6.2 or later.

## Purpose and behavior

`StrangeCore` calculates whole, halves, thirds, quadrants, and sixths using validated rectangles and shared pixel-aligned boundaries. Portrait displays keep left/center/right thirds and a three-column, two-row grid of sixths.

`AvailableSpace` reclaims the configured hidden Dock edge while preserving menu-bar and hardware-safe boundaries. `DisplayGeometry` selects a display by largest intersection and handles offscreen windows. `CoordinateSpace` converts AppKit bottom-left coordinates to Accessibility top-left coordinates. `DisplayNavigation` sorts displays left-to-right, then top-to-bottom, and wraps previous/next selection. This layer has no UI, system preference reads, Accessibility writes, network calls, or persisted user data.

## Architecture

`Sources/StrangeCore` contains pure geometry and command definitions. `Tests/StrangeCoreTests` checks partitions, invalid input, hidden-Dock space, orientation, coordinate conversion, and display order. The macOS adapter and application will build on this library.

## Bootstrap

```sh
swift build
swift test
```

`VERSION` records the semantic version. New features before 1.0 increment the minor version; compatible fixes increment the patch version.
