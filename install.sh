#!/bin/bash
# Focus installer — downloads the latest release into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/sakranolog/focus/main/install.sh | bash
set -euo pipefail

REPO="sakranolog/focus"
URL="https://github.com/$REPO/releases/latest/download/Focus.app.zip"
DEST="/Applications/Focus.app"

echo "⏳ Downloading Focus…"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL --progress-bar -o "$TMP/Focus.zip" "$URL"

echo "📦 Installing to /Applications…"
ditto -xk "$TMP/Focus.zip" "$TMP"
osascript -e 'tell application "Focus" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
ditto "$TMP/Focus.app" "$DEST"

# The app is ad-hoc signed (not notarized); clearing quarantine lets it run.
xattr -rd com.apple.quarantine "$DEST" 2>/dev/null || true

echo "✨ Done. Launching Focus…"
open "$DEST"
echo
echo "Focus lives in your menu bar. One thing at a time. 🎯"
