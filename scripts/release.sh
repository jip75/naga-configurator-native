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
BUNDLE_ID=io.mkrlab.naga-configurator-native
SHORT_VERSION=1.0.0
BUILD_VERSION=1

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/NagaConfigurator "$APP/Contents/MacOS/NagaConfigurator"
# Contents/Resources is the only location that's both a valid Bundle.main.resourceURL target AND
# something codesign will actually seal — a copy at the .app's top level (what an earlier fix here
# tried, to satisfy SwiftPM's generated Bundle.module) makes codesign fail outright with "unsealed
# contents present in the bundle root" (confirmed: --deep signing errors out, falls back to an
# adhoc signature, TeamIdentifier unset). BundleImage.swift now checks Contents/Resources itself
# instead of relying on the generated Bundle.module, so this is safe to keep here.
rsync -a --delete .build/arm64-apple-macosx/release/NagaConfigurator_NagaConfigurator.bundle/ \
    "$APP/Contents/Resources/NagaConfigurator_NagaConfigurator.bundle/"
cp build/icon.icns "$APP/Contents/Resources/AppIcon.icns"

# Without a real Info.plist, macOS can't reliably treat this folder as a proper app bundle —
# Bundle.main.resourceURL comes back wrong, so Bundle.module can never find
# NagaConfigurator_NagaConfigurator.bundle in Contents/Resources and the app hard-crashes the
# instant it tries to load a bundled image (e.g. the top bar logo).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NagaConfigurator</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Naga Configurator</string>
    <key>CFBundleDisplayName</key>
    <string>Naga Configurator</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

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
