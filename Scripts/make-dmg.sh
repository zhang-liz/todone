#!/bin/bash
# Packages build/Todone.app into a distributable .dmg with an /Applications drop target.
# Usage: Scripts/make-dmg.sh [version]   (default: version from Info.plist)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Todone.app"

if [ ! -d "$APP" ]; then
    echo "No app bundle at $APP. Run Scripts/build-app.sh first." >&2
    exit 1
fi

VERSION="${1:-$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)}"
DMG="$ROOT/build/Todone-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Todone.app"
ln -s /Applications "$STAGE/Applications"

# First-launch instructions ride along inside the disk image, since the app is
# ad-hoc signed and Gatekeeper will block a plain double-click.
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Installing Todone
=================

1. Drag Todone.app onto the Applications folder in this window.
2. Open your Applications folder.
3. Right-click (or Control-click) Todone and choose "Open".
4. Click "Open" in the dialog that appears.

Step 3 is only needed the first time. Todone is signed ad-hoc rather than
notarized by Apple, so macOS asks for confirmation on first launch. After
that it opens normally from Spotlight, Launchpad, or the Dock.

Your tasks live in ~/Library/Application Support/Todone/todone.json
TXT

rm -f "$DMG"
hdiutil create \
    -volname "Todone $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo "Built: $DMG"
