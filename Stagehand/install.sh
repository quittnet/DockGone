#!/bin/bash
set -e

# Builds Stagehand, wraps the binary in a .app bundle with a stable ad-hoc
# signature (so the Accessibility grant and SMAppService login item survive
# rebuilds), installs it to ~/Applications, and launches it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/.build/release/Stagehand"
APP="$HOME/Applications/Stagehand.app"
INFO_PLIST_SRC="$SCRIPT_DIR/Resources/Info.plist"

echo "Building (release)…"
cd "$SCRIPT_DIR"
swift build -c release

echo "Creating app bundle at $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Stagehand"
cp "$INFO_PLIST_SRC" "$APP/Contents/Info.plist"

echo "Signing (ad-hoc)…"
# A stable identity lets TCC pin the Accessibility grant and lets SMAppService
# recognise the bundle across rebuilds. Without it every rebuild re-prompts.
codesign --sign - --force --deep "$APP"

# Stop any previous copy and relaunch from the installed location. Launch-at-login
# is registered from inside the app via SMAppService (menu ▸ Launch at Login).
pkill -x Stagehand 2>/dev/null || true
open "$APP"

echo ""
echo "Done. Stagehand is running in your menu bar (look for the window icon)."
echo ""
echo "Next steps:"
echo "  1. Grant Accessibility: System Settings ▸ Privacy & Security ▸ Accessibility → enable Stagehand"
echo "  2. Open profiles, save a layout, and toggle “Launch at Login” from the menu."
