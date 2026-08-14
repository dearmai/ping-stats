#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/PingStats.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp ".build/release/PingStats" "$MACOS_DIR/PingStats"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>PingStats</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.pingstats.app</string>
    <key>CFBundleName</key>
    <string>PingStats</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026</string>
</dict>
</plist>
PLIST

RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
    scripts/generate-icon.sh >/dev/null
fi
mkdir -p "$RESOURCES_DIR"
cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"

# Localizations. Keys are the English UI text, so a missing .lproj just means
# English; without this copy the app is English-only.
for LPROJ in "$ROOT_DIR"/Resources/*.lproj; do
    [[ -d "$LPROJ" ]] || continue
    cp -R "$LPROJ" "$RESOURCES_DIR/"
done

# The Swift linker only applies a linker-signed ad-hoc signature that leaves the
# Info.plist unbound, so macOS cannot resolve the bundle identity and silently
# denies UserNotifications. A real codesign pass seals resources and binds the
# Info.plist, which is the minimum required for local notifications to work.
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"
