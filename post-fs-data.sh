#!/system/bin/sh
# Early boot: safety guards, then set the props (memory-only) and record when.

MODDIR=${0%/*}
TAG=rubyprq_on_q2
LOG="$MODDIR/run.log"

log_line() { echo "$(date '+%H:%M:%S') post-fs-data: $1" >> "$LOG"; log -t $TAG "$1" 2>/dev/null; }
rp() { resetprop -n "$1" "$2" 2>/dev/null || magisk resetprop -n "$1" "$2" 2>/dev/null; }

: > "$LOG"
NOW=$(getprop ro.build.version.incremental)
log_line "start (device=$(getprop ro.product.device) build=$NOW)"

EXPECT=$(cat "$MODDIR/build_id" 2>/dev/null)
if [ -n "$EXPECT" ] && [ "$NOW" != "$EXPECT" ]; then
  log_line "build changed ($EXPECT -> $NOW); disabling module (reinstall after checking the new firmware)"
  touch "$MODDIR/disable"
  exit 0
fi

if [ -f "$MODDIR/boot_pending" ]; then
  N=$(cat "$MODDIR/boot_fail" 2>/dev/null); N=${N:-0}; N=$((N + 1))
  echo "$N" > "$MODDIR/boot_fail"
  log_line "previous boot did not finish (count=$N)"
  if [ "$N" -ge 2 ]; then
    log_line "two unfinished boots in a row; disabling module for safety"
    touch "$MODDIR/disable"
    exit 0
  fi
else
  rm -f "$MODDIR/boot_fail"
fi
touch "$MODDIR/boot_pending"

FAILS=0
rp persist.vendor.syncbosshal.disable_fw_version_check true || FAILS=$((FAILS + 1))
rp persist.ovr.skipctrlfwupdate 1                          || FAILS=$((FAILS + 1))
rp persist.ovr.tracking.freepair 1                         || FAILS=$((FAILS + 1))

read UP _ < /proc/uptime
echo "$UP" | tr -d '.' > "$MODDIR/armed_cs"

if [ $FAILS -eq 0 ]; then
  rp debug.rubyprq.state "props set (memory-only); waiting for service.sh"
  log_line "3 props set (memory-only) at uptime ${UP}s"
else
  rp debug.rubyprq.state "WARNING: $FAILS prop(s) failed to set"
  log_line "WARNING: $FAILS prop(s) failed to set (is resetprop available?)"
fi
