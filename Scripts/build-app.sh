#!/bin/bash
set -euo pipefail

STRANGE_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$STRANGE_PROJECT_ROOT"
# A local identity contains only a public certificate selector; private keys stay in the keychain.
STRANGE_SIGNING_CONFIG="$STRANGE_PROJECT_ROOT/.strange-signing-identity"
if [[ "${STRANGE_CODESIGN_IDENTITY+x}" != "x" ]]; then
    if [[ -f "$STRANGE_SIGNING_CONFIG" ]]; then
        if [[ "$(wc -c < "$STRANGE_SIGNING_CONFIG")" -gt 512 ]] ||
           [[ "$(awk 'END { print NR }' "$STRANGE_SIGNING_CONFIG")" != "1" ]] ||
           [[ "$(LC_ALL=C tr -d '[:print:]\n' < "$STRANGE_SIGNING_CONFIG" | wc -c)" -ne 0 ]]; then
            printf 'Local signing identity must contain one nonempty printable line of at most 512 bytes.\n' >&2
            exit 1
        fi
        STRANGE_CODESIGN_IDENTITY="$(cat "$STRANGE_SIGNING_CONFIG")"
    else
        STRANGE_CODESIGN_IDENTITY="-"
    fi
fi
if [[ -z "$STRANGE_CODESIGN_IDENTITY" || ${#STRANGE_CODESIGN_IDENTITY} -gt 512 ||
      "$STRANGE_CODESIGN_IDENTITY" == *$'\n'* || "$STRANGE_CODESIGN_IDENTITY" == *$'\r'* ]]; then
    printf 'Signing identity must be nonempty, on one line, and at most 512 characters; use - for ad hoc signing.\n' >&2
    exit 1
fi

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
if [[ "$STRANGE_CODESIGN_IDENTITY" == "-" ]]; then
    printf 'Signing ad hoc: rebuilt apps may need Accessibility permission granted again.\n'
    printf 'Set STRANGE_CODESIGN_IDENTITY or .strange-signing-identity to a persistent keychain code-signing identity for permission continuity.\n'
else
    printf 'Signing with the configured keychain identity. Keep the same identity and bundle identifier for permission continuity.\n'
fi
codesign --force --sign "$STRANGE_CODESIGN_IDENTITY" "$STRANGE_BUNDLE"
codesign --verify --strict "$STRANGE_BUNDLE"
printf 'Built %s\n' "$STRANGE_BUNDLE"
