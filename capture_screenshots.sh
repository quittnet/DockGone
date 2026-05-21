#!/usr/bin/env bash
# capture_screenshots.sh — snapshot DockGone's UI for the README.
#
# Captures: menu, switcher, preferences, edit-dock, add-to-dock, attention-dot.
# Output: ./screenshots/*.png next to this script.
#
# Usage:
#   ./capture_screenshots.sh                 # all steps
#   ./capture_screenshots.sh add-to-dock     # one step
#   ./capture_screenshots.sh menu switcher   # several
#
# Steps: menu | switcher | preferences | edit-dock | add-to-dock | attention-dot | all
#
# Requirements:
#   • DockGone installed at ~/Applications/DockGone.app.
#   • Accessibility permission for the terminal running this script
#     (System Settings → Privacy & Security → Accessibility → add the terminal).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SCRIPT_DIR/screenshots"
mkdir -p "$OUT"

# --- helpers --------------------------------------------------------------

# Swift helper: print the CGWindowID of the largest visible DockGone window.
# Status item is tiny (~24×24); any open menu/panel dwarfs it.
SWIFT_HELPER=$(mktemp -t dockgone_swift.XXXXXX).swift
trap 'rm -f "$SWIFT_HELPER"' EXIT
cat > "$SWIFT_HELPER" <<'SWIFT'
import AppKit
let opts: CGWindowListOption = [.optionOnScreenOnly]
var best: (id: Int, area: CGFloat) = (-1, 0)
if let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    for w in windows where (w["kCGWindowOwnerName"] as? String) == "DockGone" {
        if let n = w["kCGWindowNumber"] as? Int,
           let b = w["kCGWindowBounds"] as? [String: CGFloat],
           let width = b["Width"], let height = b["Height"] {
            let area = width * height
            if area > best.area { best = (n, area) }
        }
    }
}
if best.id >= 0 { print(best.id) }
SWIFT

ensure_dockgone() {
  if ! pgrep -x DockGone >/dev/null; then
    echo "Launching DockGone…"
    open -a "$HOME/Applications/DockGone.app"
    sleep 2.5
  fi
}

capture_largest_window() {
  local name="$1"
  local id
  id=$(swift "$SWIFT_HELPER")
  if [[ -n "$id" ]]; then
    screencapture -o -x -l "$id" "$OUT/$name.png"
    echo "  $name.png  (window $id)"
  else
    screencapture -x "$OUT/$name.png"
    echo "  $name.png  (full screen — no DockGone window found)"
  fi
}

trigger_menu_item() {
  local item="$1"
  osascript <<EOF >/dev/null
tell application "System Events"
  tell process "DockGone"
    click menu bar item 1 of menu bar 1
    delay 0.25
    click menu item "$item" of menu 1 of menu bar item 1 of menu bar 1
  end tell
end tell
EOF
}

close_front_window() {
  osascript -e 'tell application "System Events" to keystroke "w" using {command down}' >/dev/null 2>&1 || true
  sleep 0.5
}

press_esc() {
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
}

# --- steps ----------------------------------------------------------------

shot_menu() {
  echo "[menu] Menu bar dropdown"
  osascript -e 'tell application "System Events" to tell process "DockGone" to click menu bar item 1 of menu bar 1' >/dev/null
  sleep 0.5
  capture_largest_window "01-menu"
  press_esc
  sleep 0.4
}

shot_switcher() {
  echo "[switcher] ⌥⇥ panel"
  # Hold ⌥, tap Tab, capture by window-id inside the same script, release ⌥.
  osascript <<EOF >/dev/null
tell application "System Events"
  key down option
  key code 48
  delay 0.7
  set theId to do shell script "/usr/bin/swift '$SWIFT_HELPER'"
  if theId is not "" then
    do shell script "/usr/sbin/screencapture -o -x -l " & theId & " '$OUT/02-switcher.png'"
  else
    do shell script "/usr/sbin/screencapture -x '$OUT/02-switcher.png'"
  end if
  key up option
end tell
EOF
  echo "  02-switcher.png"
  sleep 0.4
}

shot_preferences() {
  echo "[preferences] Preferences"
  trigger_menu_item "Preferences"
  sleep 1.2
  capture_largest_window "03-preferences"
  close_front_window
}

shot_edit_dock() {
  echo "[edit-dock] Edit Dock"
  trigger_menu_item "Edit Dock"
  sleep 1.2
  capture_largest_window "04-edit-dock"
  close_front_window
}

shot_add_to_dock() {
  echo "[add-to-dock] Add to Dock"
  trigger_menu_item "Add to Dock"
  sleep 1.2
  capture_largest_window "05-add-to-dock"
  close_front_window
}

shot_attention_dot() {
  echo "[attention-dot] Menu bar icon with red attention indicator"
  # Stage: open TextEdit so DockGone establishes a clean baseline, then trigger
  # a save sheet while TextEdit is inactive.
  osascript <<'STAGE' >/dev/null
tell application "TextEdit"
  activate
  if (count of documents) = 0 then make new document
  tell document 1 to set text to "DockGone attention staging — will discard"
end tell
STAGE
  sleep 0.8
  # Make TextEdit inactive so DockGone records baseline AX state (no sheet yet).
  osascript -e 'tell application "Finder" to activate' >/dev/null
  sleep 1.8
  # Re-activate TextEdit and close the doc → save sheet appears.
  osascript <<'SHEET' >/dev/null
tell application "TextEdit" to activate
delay 0.3
tell application "System Events" to keystroke "w" using {command down}
SHEET
  sleep 0.7
  # Switch away again so DockGone flags the sheet on the now-inactive app.
  osascript -e 'tell application "Finder" to activate' >/dev/null
  sleep 2.0  # let AttentionTracker poll & flag

  # Capture a tight region around DockGone's status item.
  local pos x y rx rw rh
  pos=$(osascript -e 'tell application "System Events" to tell process "DockGone" to return position of menu bar item 1 of menu bar 1')
  IFS=', ' read -r x y <<< "$pos"
  rw=80; rh=30
  rx=$(( x - 30 ))
  screencapture -x -R "${rx},0,${rw},${rh}" "$OUT/06-attention-dot.png"
  echo "  06-attention-dot.png  (region ${rx},0,${rw},${rh})"

  # Cleanup: dismiss the sheet (⌘D = Don't Save) and quit TextEdit.
  osascript <<'CLEAN' >/dev/null 2>&1 || true
tell application "TextEdit" to activate
delay 0.4
tell application "System Events" to keystroke "d" using {command down}
delay 0.4
tell application "TextEdit" to quit
CLEAN
}

# --- main -----------------------------------------------------------------

ensure_dockgone

run_step() {
  case "$1" in
    menu)          shot_menu ;;
    switcher)      shot_switcher ;;
    preferences)   shot_preferences ;;
    edit-dock)     shot_edit_dock ;;
    add-to-dock)   shot_add_to_dock ;;
    attention-dot) shot_attention_dot ;;
    *) echo "Unknown step: $1" >&2; exit 2 ;;
  esac
}

if [[ $# -eq 0 || "$1" == "all" ]]; then
  shot_menu
  shot_switcher
  shot_preferences
  shot_edit_dock
  shot_add_to_dock
  shot_attention_dot
else
  for s in "$@"; do run_step "$s"; done
fi

echo
echo "Saved to $OUT"
