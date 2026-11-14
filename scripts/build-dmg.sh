#!/bin/sh
# Release build + DMG + notarization (§10 M8).
#
# Usage:
#   scripts/build-dmg.sh                 # release build + unsigned-ready DMG (no notarize)
#   NOTARIZE=1 APPLE_ID=… APP_PASSWORD=… TEAM_ID=… scripts/build-dmg.sh
#
# Notarization uses an app-specific password (https://appleid.apple.com) or a
# stored keychain profile: NOTARY_PROFILE=… instead of APPLE_ID/APP_PASSWORD.
set -e
cd "$(dirname "$0")/.."

CONFIG=Release
APP="TokenTank"
DMG="TokenTank.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "== building $APP ($CONFIG)"
xcodebuild -scheme "$APP" -configuration "$CONFIG" -destination 'platform=macOS' \
    -allowProvisioningUpdates build >/dev/null

BIN=$(xcodebuild -scheme "$APP" -configuration "$CONFIG" -destination 'platform=macOS' \
    -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')
APP_PATH="$BIN/$APP.app"
[ -d "$APP_PATH" ] || { echo "build product not found: $APP_PATH" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>/dev/null \
    || echo "warning: code signature verification failed" >&2

echo "== staging DMG"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "== creating $DMG"
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ "$NOTARIZE" != "1" ]; then
    echo "== done (no notarization; NOTARIZE=1 to submit)"
    exit 0
fi

echo "== submitting to notary service"
if [ -n "$NOTARY_KEY" ]; then
    xcrun notarytool submit "$DMG" --wait \
        --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
elif [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$DMG" --wait --keychain-profile "$NOTARY_PROFILE"
elif [ -n "$APPLE_ID" ] && [ -n "$APP_PASSWORD" ]; then
    xcrun notarytool submit "$DMG" --wait \
        --apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$TEAM_ID"
else
    echo "notarization creds missing: set NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER," >&2
    echo "NOTARY_PROFILE, or APPLE_ID/APP_PASSWORD/TEAM_ID" >&2
    exit 1
fi

xcrun stapler staple "$DMG"
echo "== done: $DMG (notarized + stapled)"
