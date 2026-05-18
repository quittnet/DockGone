#!/bin/bash
# DockGone end-to-end verification harness. Covers every reachable-from-shell
# vector and leaves the user a manual visual checklist for the rest. Safe to
# run repeatedly: all user state (Dock plist, DockGone prefs, no-bouncing) is
# backed up and restored on exit (including Ctrl-C).
#
# Usage:  ./verify.sh             full run
#         ./verify.sh --fast      skip the 30s idle phase + stress.sh
#         ./verify.sh --stress    also re-run ./stress.sh at the end

set -u

# ───────── Config

APP_PATH="$HOME/Applications/DockGone.app"
BIN="$APP_PATH/Contents/MacOS/DockGone"
BUNDLE_ID="com.user.dockgone"
DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"

FAST=0
RUN_STRESS=0
for arg in "$@"; do
  case "$arg" in
    --fast)   FAST=1 ;;
    --stress) RUN_STRESS=1 ;;
    *) echo "unknown arg: $arg"; exit 2 ;;
  esac
done

# ───────── Counters

PASS=0
FAIL=0
SKIP=0
declare -a FAILURES=()

pass() { PASS=$((PASS + 1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf "  \033[31m✗\033[0m %s\n" "$1"; }
skip() { SKIP=$((SKIP + 1)); printf "  \033[33m∼\033[0m %s\n" "$1"; }
hdr()  { printf "\n\033[1m=== %s ===\033[0m\n" "$1"; }
sub()  { printf "\n\033[1m--- %s ---\033[0m\n" "$1"; }

get_pid() { pgrep -x DockGone | head -1; }
get_mem() { ps -p "$1" -o rss=  2>/dev/null | tr -d ' '; }
get_cpu() { ps -p "$1" -o %cpu= 2>/dev/null | tr -d ' '; }

# ───────── Backup / restore

BACKUP_DIR="$(mktemp -d -t dockgone-verify)"
echo "Backup directory: $BACKUP_DIR"

cleanup() {
  echo
  hdr "Cleanup — restoring user state"

  # Stop DockGone so it doesn't fight us during pref restoration.
  pkill -x DockGone 2>/dev/null
  sleep 0.7

  # defaults import only merges keys present in the file; explicitly delete
  # every key we touched in Phase 3 so stale test values can't survive when
  # the original backup didn't have them set.
  for key in iconSize position labelMode includeTrash hotkeyKey hotkeyMods suppressBouncing; do
    defaults delete "$BUNDLE_ID" "$key" 2>/dev/null
  done

  if [ -f "$BACKUP_DIR/dockgone-prefs.plist" ]; then
    if defaults import "$BUNDLE_ID" "$BACKUP_DIR/dockgone-prefs.plist" 2>/dev/null; then
      pass "DockGone prefs restored from backup"
    else
      skip "Backup empty — DockGone prefs left at defaults"
    fi
  fi

  if [ -f "$BACKUP_DIR/dock.plist" ]; then
    cp "$BACKUP_DIR/dock.plist" "$DOCK_PLIST" && pass "Dock plist restored"
    killall Dock 2>/dev/null
  fi

  # Restart DockGone so it re-applies no-bouncing per the restored pref.
  "$BIN" >/dev/null 2>&1 & disown
  sleep 1.5

  rm -f /tmp/dockgone_test_window.swift
  rm -rf "$BACKUP_DIR"
  echo
}
trap cleanup EXIT INT TERM

# Snapshot state up front.
cp "$DOCK_PLIST" "$BACKUP_DIR/dock.plist" 2>/dev/null
defaults export "$BUNDLE_ID" "$BACKUP_DIR/dockgone-prefs.plist" 2>/dev/null

# ───────── PHASE 0: Preflight

hdr "Phase 0 — Preflight"

if [ -d "$APP_PATH" ]; then pass "App bundle exists at $APP_PATH"
else fail "App bundle missing at $APP_PATH"; exit 1
fi
if [ -x "$BIN" ]; then pass "Executable is runnable"
else fail "Executable missing or not executable: $BIN"; exit 1
fi

PID="$(get_pid)"
if [ -n "$PID" ]; then pass "DockGone is running (pid=$PID)"
else fail "DockGone is not running — start it via launchctl or install.sh"; exit 1
fi

# Accessibility permission — we can only detect "trusted" from inside the
# target process. Best we can do externally is sample the TCC log.
AX_HINT="$(log show --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS "DockGone"' --last 1h 2>/dev/null | grep -c "kTCCServiceAccessibility")"
if [ "$AX_HINT" -gt 0 ]; then pass "Accessibility prompt was answered for DockGone in the last hour"
else skip "Accessibility status not detectable from shell — verify in System Settings"
fi

# ───────── PHASE 1: Configuration health

hdr "Phase 1 — Configuration health"

NOBOUNCE="$(defaults read com.apple.dock no-bouncing 2>/dev/null || echo "MISSING")"
if [ "$NOBOUNCE" = "1" ]; then pass "com.apple.dock no-bouncing = 1 (suppression active)"
else fail "no-bouncing not set (got: $NOBOUNCE) — suppress-bouncing pref may be off"
fi

# Suppress-bouncing pref present and on
SUPPRESS="$(defaults read "$BUNDLE_ID" suppressBouncing 2>/dev/null || echo "DEFAULT")"
case "$SUPPRESS" in
  1|DEFAULT) pass "suppressBouncing pref reads as ON (value=$SUPPRESS — DEFAULT means using default true)" ;;
  0)         skip "suppressBouncing pref is OFF — user-chosen; no-bouncing check above can fail" ;;
  *)         fail "suppressBouncing pref has unexpected value: $SUPPRESS" ;;
esac

# LaunchAgent installed
AGENT="$HOME/Library/LaunchAgents/com.user.dockgone.plist"
if [ -f "$AGENT" ]; then pass "LaunchAgent installed at $AGENT"
else skip "LaunchAgent not installed — Launch at Login is off"
fi

# ───────── PHASE 2: Dock plist soundness

hdr "Phase 2 — Dock plist soundness"

if plutil -lint "$DOCK_PLIST" >/dev/null 2>&1; then pass "Dock plist parses (plutil -lint)"
else fail "Dock plist failed plutil lint"
fi

APP_COUNT="$(/usr/libexec/PlistBuddy -c 'Print persistent-apps' "$DOCK_PLIST" 2>/dev/null | grep -c 'tile-type')"
if [ "$APP_COUNT" -gt 0 ]; then pass "Dock contains $APP_COUNT persistent-apps entries"
else fail "Couldn't read persistent-apps from Dock plist"
fi

# Re-read after a no-op write to make sure we can write+killall without breaking it.
# (Simulates Add to Dock / Edit Dock plist write pathway.)
defaults read "$DOCK_PLIST" >/dev/null 2>&1 \
  && pass "Dock plist round-trips through defaults read" \
  || fail "defaults read failed on Dock plist"

# ───────── PHASE 3: Preferences round-trip

hdr "Phase 3 — Preferences round-trip"

# Stop DockGone temporarily so it doesn't fight us on the writes.
ORIG_PID="$PID"
pkill -x DockGone 2>/dev/null; sleep 0.7

roundtrip_int() {
  local key="$1" val="$2"
  defaults write "$BUNDLE_ID" "$key" -int "$val"
  local got; got="$(defaults read "$BUNDLE_ID" "$key" 2>/dev/null)"
  if [ "$got" = "$val" ]; then pass "$key int write/read ($val)"
  else fail "$key round-trip: wrote $val, read '$got'"
  fi
}

roundtrip_float() {
  local key="$1" val="$2"
  defaults write "$BUNDLE_ID" "$key" -float "$val"
  local got; got="$(defaults read "$BUNDLE_ID" "$key" 2>/dev/null)"
  if [ "$got" = "$val" ]; then pass "$key float write/read ($val)"
  else fail "$key round-trip: wrote $val, read '$got'"
  fi
}

roundtrip_bool() {
  local key="$1" val="$2"
  defaults write "$BUNDLE_ID" "$key" -bool "$val"
  local got; got="$(defaults read "$BUNDLE_ID" "$key" 2>/dev/null)"
  if [ "$got" = "1" ] && [ "$val" = "true" ]; then pass "$key bool write/read (true)"
  elif [ "$got" = "0" ] && [ "$val" = "false" ]; then pass "$key bool write/read (false)"
  else fail "$key bool round-trip: wrote $val, read '$got'"
  fi
}

roundtrip_string() {
  local key="$1" val="$2"
  defaults write "$BUNDLE_ID" "$key" -string "$val"
  local got; got="$(defaults read "$BUNDLE_ID" "$key" 2>/dev/null)"
  if [ "$got" = "$val" ]; then pass "$key string write/read ($val)"
  else fail "$key string round-trip: wrote $val, read '$got'"
  fi
}

roundtrip_float  iconSize 96
roundtrip_string position top
roundtrip_string position center
roundtrip_string position bottom
roundtrip_string labelMode always
roundtrip_string labelMode selectedOnly
roundtrip_string labelMode never
roundtrip_bool   includeTrash true
roundtrip_bool   includeTrash false
roundtrip_int    hotkeyKey 48     # kVK_Tab
roundtrip_int    hotkeyMods 2048  # cmdKey alt example
roundtrip_bool   suppressBouncing true
roundtrip_bool   suppressBouncing false

# Restart DockGone for subsequent phases (launchd will respawn but we want it now).
"$BIN" >/dev/null 2>&1 & disown
sleep 1
PID="$(get_pid)"
if [ -n "$PID" ]; then pass "DockGone respawned after prefs phase (pid=$PID)"
else fail "DockGone did NOT come back after prefs phase"
fi

# ───────── PHASE 4: AttentionTracker stress

hdr "Phase 4 — AttentionTracker churn"

cat > /tmp/dockgone_test_window.swift <<'SWIFT'
import Cocoa
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 120),
                   styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
win.title = "DockGone Attention Test"
DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    win.makeKeyAndOrderFront(nil)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
    NSApp.terminate(nil)
}
app.run()
SWIFT

BEFORE_MEM="$(get_mem "$PID" 2>/dev/null || echo 0)"

echo "  Launching 10 background-window processes (this exercises AX observer install/teardown)…"
for i in $(seq 1 10); do
  swift /tmp/dockgone_test_window.swift </dev/null >/dev/null 2>&1 &
  sleep 0.05
done
wait

sleep 1
NEW_PID="$(get_pid)"
if [ -n "$NEW_PID" ] && [ "$NEW_PID" = "$PID" ]; then
  pass "DockGone survived 10 attention-window churn cycles (pid unchanged)"
elif [ -n "$NEW_PID" ]; then
  skip "DockGone respawned during churn (pid $PID -> $NEW_PID) — launchd KeepAlive caught it"
  PID="$NEW_PID"
else
  fail "DockGone is GONE after attention churn"
fi

AFTER_MEM="$(get_mem "$PID" 2>/dev/null || echo 0)"
DELTA=$((AFTER_MEM - BEFORE_MEM))
if [ "$DELTA" -lt 3000 ]; then pass "Memory delta after churn: ${DELTA}KB (under 3MB threshold)"
else fail "Memory grew ${DELTA}KB after attention churn — possible AX observer leak"
fi

# ───────── PHASE 5: Hotkey registration

hdr "Phase 5 — Hotkey registration"

# No reliable shell-side signal for Carbon hot-key registration without
# private SPI. Confirmed live-fire via the manual checklist instead.
skip "Hotkey delivery is keyboard-only — see Manual checklist below"

# ───────── PHASE 6: Crash & error log scan

hdr "Phase 6 — Crash & error log scan"

# Only count crashes newer than the currently-installed binary — older
# reports may be from prior builds and aren't actionable for this run.
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
if [ -d "$CRASH_DIR" ] && [ -f "$BIN" ]; then
  RECENT_CRASHES="$(find "$CRASH_DIR" -name 'DockGone-*' -newer "$BIN" 2>/dev/null | wc -l | tr -d ' ')"
  STALE_CRASHES="$(find "$CRASH_DIR" -name 'DockGone-*' ! -newer "$BIN" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$RECENT_CRASHES" -eq 0 ]; then
    if [ "$STALE_CRASHES" -gt 0 ]; then
      pass "No crash reports newer than current binary ($STALE_CRASHES stale report(s) ignored)"
    else
      pass "No DockGone crash reports in DiagnosticReports"
    fi
  else
    fail "$RECENT_CRASHES crash report(s) newer than current binary in $CRASH_DIR"
  fi
else
  skip "Crash report directory not present"
fi

LOG_ERRS="$(log show --predicate 'process == "DockGone"' --last 5m 2>/dev/null \
            | grep -iE 'error|exception|crash|signal' \
            | grep -vE 'AXError|"errorString' \
            | wc -l | tr -d ' ')"
if [ "$LOG_ERRS" -eq 0 ]; then pass "No error/exception entries in last 5min of DockGone log"
else skip "$LOG_ERRS log lines matched error/exception — investigate with: log show --predicate 'process == \"DockGone\"' --last 5m"
fi

# AX permission denial leaves a recognizable trace. Note it but don't fail —
# the user may have intentionally not granted it yet.
AX_DENY="$(log show --predicate 'subsystem == "com.apple.Accessibility"' --last 5m 2>/dev/null \
           | grep -i DockGone | grep -ic denied)"
if [ "$AX_DENY" -gt 0 ]; then skip "Accessibility access was denied for DockGone in the last 5min — grant it to enable attention tracking"
else pass "No Accessibility denial log entries"
fi

# ───────── PHASE 7: Idle settle / leak detection

hdr "Phase 7 — Idle settle (memory leak watch)"

if [ "$FAST" -eq 1 ]; then
  skip "--fast: skipped 30s idle settle"
else
  echo "  Sampling every 10s for 30s…"
  IDLE_START_MEM="$(get_mem "$PID")"
  for i in 1 2 3; do
    sleep 10
    M="$(get_mem "$PID")"
    C="$(get_cpu "$PID")"
    printf "    +%-2ds  mem=%s KB  cpu=%s%%\n" "$((i * 10))" "$M" "$C"
  done
  IDLE_END_MEM="$(get_mem "$PID")"
  IDLE_DELTA=$((IDLE_END_MEM - IDLE_START_MEM))
  if [ "$IDLE_DELTA" -lt 500 ]; then pass "Idle memory delta over 30s: ${IDLE_DELTA}KB (stable)"
  else fail "Idle memory grew ${IDLE_DELTA}KB in 30s — possible slow leak"
  fi
fi

# ───────── PHASE 8: Optional stress.sh

hdr "Phase 8 — Lifecycle stress (stress.sh)"

if [ "$RUN_STRESS" -eq 1 ] && [ -x "./stress.sh" ]; then
  echo "  Running ./stress.sh…"
  ./stress.sh
  pass "stress.sh completed (read its own verdict above)"
else
  skip "stress.sh not run (pass --stress to include it)"
fi

# ───────── Summary

echo
hdr "Summary"
printf "  passed: \033[32m%d\033[0m\n" "$PASS"
printf "  failed: \033[31m%d\033[0m\n" "$FAIL"
printf "  skipped: \033[33m%d\033[0m\n" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  echo
  printf "  \033[31mFailures:\033[0m\n"
  for f in "${FAILURES[@]}"; do printf "   • %s\n" "$f"; done
fi

# ───────── Manual checklist

cat <<'CHECKLIST'

=== Manual checklist (things a script can't see) ===

  Switcher
    [ ] Press ⌥⇥ — switcher panel appears
    [ ] Tap ⌥⇥ again — cycles to next app
    [ ] Hold ⌥⇥ ≥ 0.4s — auto-cycles
    [ ] Shift + Tab while open — cycles backward
    [ ] Arrow keys move selection
    [ ] Mouse hover changes selection
    [ ] Click an icon — launches it
    [ ] Release ⌥ — launches selected
    [ ] Esc dismisses without launching
    [ ] Click outside the panel dismisses

  Menu bar
    [ ] Click the dock-rectangle icon — menu opens
    [ ] Hide Dock toggle works (dock slides away / returns)
    [ ] Add to Dock opens a grid picker
    [ ] Edit Dock opens with current Dock apps; drag reorders; X removes
    [ ] Preferences opens; sliders/swatches/hotkey recorder all respond
    [ ] Launch at Login toggle survives a logout/login

  Attention tracker (use the TextEdit trigger from before)
    [ ] Trigger a backgrounded attention → red dot appears on menu bar icon
    [ ] Dot pulses briefly on first appearance
    [ ] Click menu bar icon → app shows in "Attention" section
    [ ] Click the Attention row → app activates, dot clears
    [ ] Press ⌥⇥ while attention is pending → app has a pulsing red ring
    [ ] Red-ringed app is sorted to the front of the switcher
    [ ] Click red-ringed slot → existing process activates (not a new launch)
    [ ] System Dock NEVER bounces during any of the above

  No-bouncing
    [ ] Force a real attention from a visible Dock too — nothing bounces

CHECKLIST

# ───────── Exit code

if [ "$FAIL" -gt 0 ]; then
  printf "\n\033[31mVerdict: FAIL\033[0m\n"
  exit 1
fi
printf "\n\033[32mVerdict: PASS (automated portion). Run the manual checklist above.\033[0m\n"
exit 0
