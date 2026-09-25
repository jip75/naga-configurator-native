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
SHORT_VERSION=1.1.1
BUILD_VERSION=3

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
# Stage in a folder alongside a symlink to /Applications — a bare -srcfolder "$APP" drops the
# .app in with no drag-to-install affordance, so a first-time user has to run it straight from
# the mounted volume instead of dragging it in like every other Mac app.
STAGING=build/dmg-staging
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Naga Configurator" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Signing DMG with Developer ID"
# The .app inside is notarized+stapled above, but the DMG container itself was shipping
# unsigned — spctl --type open rejects an unsigned, unstapled DMG ("Insufficient Context").
# It doesn't hard-block a launch (Gatekeeper's real checkpoint is the .app, which macOS runs via
# App Translocation regardless), but it's not the clean "double-click, no warnings" experience
# the download page promises, so sign+notarize+staple the DMG too, same as the app.
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
codesign -dv --verbose=2 "$DMG"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing DMG (profile '$NOTARY_PROFILE' found)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
else
    echo "==> Skipping DMG notarization: no keychain profile named '$NOTARY_PROFILE'."
fi

echo "==> Gatekeeper check (app)"
spctl -a -vv --type execute "$APP" || true

echo "==> Gatekeeper check (dmg)"
# A bare disk image needs --context context:primary-signature or spctl misreports a correctly
# notarized/stapled DMG as "rejected, source=Insufficient Context" — confirmed by hand 2026-09-25,
# not a real Gatekeeper problem, just the wrong spctl invocation for testing a standalone DMG.
spctl -a -vv --type open --context context:primary-signature "$DMG" || true

echo "Done: $APP, $DMG"
