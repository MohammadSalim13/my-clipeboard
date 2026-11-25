#!/bin/bash
# Builds the app, copies it to /Applications and starts it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Clipboard History"
BUNDLE_ID="local.ClipboardHistory"
DEST="/Applications/$APP_NAME.app"

./build.sh

echo "▸ Installing to $DEST"
pkill -x ClipboardHistory 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "build/$APP_NAME.app" "$DEST"

# Every build has a new signature, so an older Accessibility approval no longer matches it.
# Clear it so macOS asks again cleanly instead of silently ignoring the old switch.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

open "$DEST"
echo "✔ Installed. Look for the clipboard icon in the menu bar, then press ⌥V."
