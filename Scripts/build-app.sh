#!/bin/bash
# Assembles Todone.app from the SPM release build.
# Usage: Scripts/build-app.sh [debug|release]  (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Todone.app"

cd "$ROOT"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Todone"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Todone"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Todone</string>
    <key>CFBundleIdentifier</key>
    <string>com.lzhang.todone</string>
    <key>CFBundleName</key>
    <string>Todone</string>
    <key>CFBundleDisplayName</key>
    <string>Todone</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

if [ -f "$ROOT/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built: $APP"
