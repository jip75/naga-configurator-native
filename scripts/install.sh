#!/bin/bash
# Drag-and-drop installer for Naga Configurator on a new/work Mac.
# Finds the DMG, clears Gatekeeper quarantine, installs to /Applications, and launches it.
#
# Usage:
#   ./install.sh                      # looks in ~/Downloads for NagaConfigurator.dmg
#   ./install.sh /path/to/NagaConfigurator.dmg
set -euo pipefail

APP_NAME="Naga Configurator.app"
DMG="${1:-$HOME/Downloads/NagaConfigurator.dmg}"

if [[ ! -f "$DMG" ]]; then
    echo "Error: DMG not found at $DMG"
    echo "Pass the path explicitly: ./install.sh /path/to/NagaConfigurator.dmg"
    exit 1
fi

echo "==> Clearing quarantine on $DMG"
xattr -d com.apple.quarantine "$DMG" 2>/dev/null || true

echo "==> Mounting"
MOUNT_POINT=$(hdiutil attach "$DMG" -nobrowse | tail -1 | awk -F'\t' '{print $NF}')
echo "    mounted at $MOUNT_POINT"

SRC_APP="$MOUNT_POINT/$APP_NAME"
if [[ ! -d "$SRC_APP" ]]; then
    SRC_APP=$(find "$MOUNT_POINT" -maxdepth 1 -iname "*.app" | head -1)
fi
if [[ -z "$SRC_APP" || ! -d "$SRC_APP" ]]; then
    echo "Error: no .app found inside $MOUNT_POINT"
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    exit 1
fi

DEST="/Applications/$(basename "$SRC_APP")"
echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$SRC_APP" "$DEST"

echo "==> Ejecting DMG"
hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true

echo "==> Clearing quarantine on installed app (recursive)"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Gatekeeper check"
spctl -a -vv --type execute "$DEST" || true

echo "==> Launching"
open "$DEST"

echo "Done."
