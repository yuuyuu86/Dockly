#!/bin/bash
# Notarises and staples build/Dockly.app, then writes build/Dockly.zip.
#
# Needs a Developer ID build (DOCKLY_SIGN_IDENTITY set when running build.sh)
# and notarytool credentials. Store them once with:
#
#   xcrun notarytool store-credentials dockly \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# then:  ./Tools/notarize.sh [keychain-profile]
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${1:-dockly}"
APP="build/Dockly.app"
ZIP="build/Dockly.zip"

[ -d "$APP" ] || { echo "No $APP — run ./build.sh release first." >&2; exit 1; }

if codesign -dvv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
  echo "$APP is ad-hoc signed. Set DOCKLY_SIGN_IDENTITY and rebuild." >&2
  exit 1
fi

echo "▸ Packaging…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to Apple…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ Repackaging the stapled app…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ Notarised: $ZIP"
