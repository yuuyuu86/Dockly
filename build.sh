#!/bin/bash
# Builds Dockly.app into ./build/
#
# Ad-hoc signed by default, which is enough to run on this Mac. To produce a
# build other Macs will open, export a Developer ID identity first:
#
#   export DOCKLY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   ./build.sh release
#   ./Tools/notarize.sh          # staples the Apple ticket
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/Dockly.app"
IDENTITY="${DOCKLY_SIGN_IDENTITY:-}"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --disable-sandbox

BIN=".build/$CONFIG/Dockly"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dockly"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for lproj in Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "$IDENTITY" ]; then
  echo "▸ Signing with Developer ID…"
  # A hardened runtime is what notarisation requires; the entitlements keep
  # Apple Events and Location working under it.
  codesign --force --options runtime --timestamp \
    --entitlements Resources/Dockly.entitlements \
    --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  echo "✓ Signed as: $IDENTITY"
else
  echo "▸ Signing (ad-hoc — this Mac only)…"
  codesign --force --entitlements Resources/Dockly.entitlements --sign - "$APP" 2>/dev/null \
    || codesign --force --sign - "$APP"
fi

echo "✓ Built $APP"
