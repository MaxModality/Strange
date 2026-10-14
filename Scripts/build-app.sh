#!/bin/bash
set -euo pipefail

STRANGE_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$STRANGE_PROJECT_ROOT"
swift build -c release -debug-info-format none
STRANGE_BIN_DIR="$(swift build -c release --show-bin-path)"
STRANGE_VERSION="$(cat VERSION)"
if [[ ! "$STRANGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'VERSION must contain a semantic version.\n' >&2
    exit 1
fi
STRANGE_ICON_DIR="$STRANGE_PROJECT_ROOT/.build/icons"
STRANGE_BUNDLE="$STRANGE_PROJECT_ROOT/.build/Strange.app"

"$STRANGE_BIN_DIR/strange-app" --export-icons "$STRANGE_ICON_DIR"
mkdir -p "$STRANGE_BUNDLE/Contents/MacOS" "$STRANGE_BUNDLE/Contents/Resources"
cp "$STRANGE_BIN_DIR/strange-app" "$STRANGE_BUNDLE/Contents/MacOS/strange-app"
iconutil --convert icns "$STRANGE_ICON_DIR/Strange.iconset" --output "$STRANGE_BUNDLE/Contents/Resources/Strange.icns"
cat > "$STRANGE_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Strange</string>
    <key>CFBundleDisplayName</key><string>Strange</string>
    <key>CFBundleIdentifier</key><string>local.strange.windowmanager</string>
    <key>CFBundleExecutable</key><string>strange-app</string>
    <key>CFBundleIconFile</key><string>Strange.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$STRANGE_VERSION</string>
    <key>CFBundleVersion</key><string>$STRANGE_VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict></plist>
PLIST
plutil -lint "$STRANGE_BUNDLE/Contents/Info.plist"
codesign --force --sign - "$STRANGE_BUNDLE"
codesign --verify --strict "$STRANGE_BUNDLE"
printf 'Built %s\n' "$STRANGE_BUNDLE"
