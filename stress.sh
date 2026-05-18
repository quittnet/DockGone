#!/bin/bash
# DockGone stress harness. Exercises the lifecycle vectors reachable
# from a shell (no Accessibility): kill/respawn, plist battering, and
# long-run idle memory monitoring. Reports a metrics timeline so leaks
# or respawn failures show up.
set -u

APP_PATH=/Users/zq/Applications/DockGone.app
BIN=$APP_PATH/Contents/MacOS/DockGone

get_pid()  { pgrep -f "$BIN" | head -1; }
get_mem()  { ps -p "$1" -o rss=    2>/dev/null | tr -d ' '; }
get_cpu()  { ps -p "$1" -o %cpu=   2>/dev/null | tr -d ' '; }
get_thr()  { ps -p "$1" -M         2>/dev/null | tail -n +2 | wc -l | tr -d ' '; }
get_fd()   { lsof -p "$1"          2>/dev/null | wc -l | tr -d ' '; }
ts()       { date +%H:%M:%S; }

sample() {
  local pid mem cpu thr fd
  pid=$(get_pid)
  if [ -z "$pid" ]; then printf '[%s] %-22s NO PID\n' "$(ts)" "$1"; return; fi
  mem=$(get_mem "$pid"); cpu=$(get_cpu "$pid")
  thr=$(get_thr "$pid"); fd=$(get_fd "$pid")
  printf '[%s] %-22s pid=%-6s mem=%-7sKB cpu=%-5s%% thr=%-3s fd=%s\n' \
    "$(ts)" "$1" "$pid" "$mem" "$cpu" "$thr" "$fd"
}

echo "=== DockGone stress test ==="
echo "Started: $(date)"
echo

PID=$(get_pid)
if [ -z "$PID" ]; then echo "FAIL: DockGone not running at start"; exit 1; fi
sample "baseline"
BASELINE_MEM=$(get_mem "$PID")
BASELINE_FD=$(get_fd "$PID")

# ───────── Phase 1: SIGTERM / launchd-respawn churn ─────────
# launchd KeepAlive throttleTimeout = 10s by default, so we pause >10s
# between kills. Trying to kill faster than that just trips the throttle,
# which is correct behavior (crash-loop protection) but indistinguishable
# from a real respawn failure unless we slow down.
ITERS=10
SPACING=11
echo
echo "--- Phase 1: ${ITERS}x SIGTERM with ${SPACING}s spacing (respects launchd throttle) ---"
TOTAL_MS=0
FAILED=0
for i in $(seq 1 $ITERS); do
  P=$(get_pid)
  if [ -z "$P" ]; then echo "  iter=$i: no pid (lost ground); waiting"; sleep 2; continue; fi
  T0=$(($(date +%s%N) / 1000000))
  kill -TERM "$P" 2>/dev/null
  OK=0
  # Allow up to 15s for launchd to respawn (10s throttle + 5s slack).
  for _ in $(seq 1 150); do
    NEW=$(get_pid)
    if [ -n "$NEW" ] && [ "$NEW" != "$P" ]; then
      T1=$(($(date +%s%N) / 1000000))
      DT=$((T1 - T0))
      TOTAL_MS=$((TOTAL_MS + DT))
      OK=1
      break
    fi
    sleep 0.1
  done
  if [ $OK -eq 0 ]; then
    FAILED=$((FAILED + 1))
    echo "  iter=$i: did NOT respawn within 15s"
  fi
  [ $i -lt $ITERS ] && sleep $SPACING
done
SUCCESS=$((ITERS - FAILED))
if [ $SUCCESS -gt 0 ]; then AVG=$((TOTAL_MS / SUCCESS)); else AVG=0; fi
echo "  respawned: $SUCCESS/$ITERS   avg=${AVG}ms"
sample "after kill/respawn"

# ───────── Phase 2: rapid plist reads ─────────
echo
echo "--- Phase 2: 1000x rapid plist reads ---"
T0=$(($(date +%s%N) / 1000000))
for i in $(seq 1 1000); do defaults read com.user.dockgone >/dev/null 2>&1; done
T1=$(($(date +%s%N) / 1000000))
echo "  1000 reads in $((T1 - T0))ms"
sample "after plist reads"

# ───────── Phase 3: rapid plist writes against stress keys ─────────
echo
echo "--- Phase 3: 1000x plist writes (rotating keys) ---"
T0=$(($(date +%s%N) / 1000000))
for i in $(seq 1 1000); do
  defaults write com.user.dockgone "stressKey_$((i % 10))" -int "$i" 2>/dev/null
done
T1=$(($(date +%s%N) / 1000000))
echo "  1000 writes in $((T1 - T0))ms"
for i in 0 1 2 3 4 5 6 7 8 9; do
  defaults delete com.user.dockgone "stressKey_$i" 2>/dev/null
done
sample "after plist writes"

# ───────── Phase 4: 30s idle settle ─────────
echo
echo "--- Phase 4: 30s idle settle, sample every 10s ---"
for i in 1 2 3; do
  sleep 10
  sample "idle +${i}0s"
done

# ───────── Summary ─────────
echo
FINAL_PID=$(get_pid)
FINAL_MEM=$(get_mem "$FINAL_PID")
FINAL_FD=$(get_fd "$FINAL_PID")
sample "final"

echo
echo "=== Summary ==="
echo "memory: ${BASELINE_MEM}KB -> ${FINAL_MEM}KB (delta $((FINAL_MEM - BASELINE_MEM))KB)"
echo "fds:    ${BASELINE_FD} -> ${FINAL_FD} (delta $((FINAL_FD - BASELINE_FD)))"
echo "respawn failures: $FAILED/$ITERS"
PASS_FAIL="PASS"
if [ "$FAILED" -gt 0 ]; then PASS_FAIL="FAIL (respawn)"; fi
if [ -z "$FINAL_PID" ]; then PASS_FAIL="FAIL (process gone)"; fi
DELTA_MEM=$((FINAL_MEM - BASELINE_MEM))
if [ "$DELTA_MEM" -gt 5000 ]; then PASS_FAIL="$PASS_FAIL (mem grew >${DELTA_MEM}KB)"; fi
echo "Verdict: $PASS_FAIL"
