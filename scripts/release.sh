#!/bin/bash
# Builds a release binary, assembles build/NagaConfigurator.app, signs it with the Developer ID
# identity (hardened runtime — required for notarization), and packages a DMG.
#
# Notarization is opt-in: it only runs if a `xcrun notarytool` keychain profile named
# NOTARY_PROFILE (default "naga-notary") already exists. Create one ONCE, yourself, with your own
# Apple ID app-specific password (id.apple.com > Sign-In and Security > App-Specific Passwords) —
# this script never asks for or sees that password:
#   xcrun notarytool store-credentials naga-notary \
#     --apple-id <your-apple-id-email> --team-id U634VN98C4 --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Jorge Pichardo (U634VN98C4)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-naga-notary}"
APP=build/NagaConfigurator.app
DMG=build/NagaConfigurator.dmg

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/NagaConfigurator "$APP/Contents/MacOS/NagaConfigurator"
rsync -a --delete .build/arm64-apple-macosx/release/NagaConfigurator_NagaConfigurator.bundle/ \
    "$APP/Contents/Resources/NagaConfigurator_NagaConfigurator.bundle/"
cp build/icon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing with Developer ID (hardened runtime)"
codesign --force --deep --options runtime \
    --entitlements NagaConfigurator.entitlements \
    --sign "$SIGN_IDENTITY" \
    --timestamp \
    "$APP"
codesign -dv --verbose=2 "$APP"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing (profile '$NOTARY_PROFILE' found)"
    ZIP=build/NagaConfigurator-notarize.zip
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
else
    echo "==> Skipping notarization: no keychain profile named '$NOTARY_PROFILE'."
    echo "    Gatekeeper will still block this build on other Macs until it's notarized — see"
    echo "    the comment at the top of this script for the one-time setup command."
fi

echo "==> Building DMG"
rm -f "$DMG"
hdiutil create -volname "Naga Configurator" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Gatekeeper check"
spctl -a -vv --type execute "$APP" || true

echo "Done: $APP, $DMG"
