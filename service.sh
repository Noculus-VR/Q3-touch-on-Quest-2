#!/system/bin/sh
# Late boot: the props are only read when a service starts. If the sensors HAL
# or the controller management service started before post-fs-data set them
# (Magisk may run late on this device), restart each stale one once.
#
# Services are found by which process has the library mapped, so no service
# names are hard-coded.

MODDIR=${0%/*}
TAG=rubyprq_on_q2
LOG="$MODDIR/run.log"
CMS_LIB=${CMS_LIB:-libcmsservice-headset.so}
HAL_LIB=${HAL_LIB:-libsyncboss.so}
CLK=$(getconf CLK_TCK 2>/dev/null); CLK=${CLK:-100}
# never restart these, whatever maps the libraries
DENY='init|ueventd|logd|servicemanager|hwservicemanager|vndservicemanager|zygote|zygote_secondary|surfaceflinger|vold|netd|adbd|keystore'

log_line() { echo "$(date '+%H:%M:%S') service: $1" >> "$LOG"; log -t $TAG "$1" 2>/dev/null; }
state()    { resetprop -n debug.rubyprq.state "$1" 2>/dev/null || magisk resetprop -n debug.rubyprq.state "$1" 2>/dev/null; log_line "$1"; }
finish()   { rm -f "$MODDIR/boot_pending" "$MODDIR/boot_fail"; exit 0; }

# PIDs (max 5) of processes that have $1 mapped
lib_pids() {
  grep -l "$1" /proc/[0-9]*/maps 2>/dev/null | head -5 | while IFS=/ read -r _ _ p _; do echo "$p"; done
}

# init service name for a pid: init.svc_debug_pid first, then the .rc files
svc_from_rc() {
  local exe line
  exe=$(readlink "/proc/$1/exe" 2>/dev/null)
  [ -n "$exe" ] || return
  line=$(grep -h -E "^service +[^ ]+ +$exe( |\$)" \
    /system/etc/init/*.rc /system_ext/etc/init/*.rc /vendor/etc/init/*.rc \
    /odm/etc/init/*.rc /product/etc/init/*.rc 2>/dev/null | head -1)
  [ -n "$line" ] || return
  set -- $line
  echo "$2"
}

svc_for_pid() {
  local p="$1" l n out
  out=$(getprop | grep '^\[init\.svc_debug_pid\.' | while IFS= read -r l; do
    if [ "${l##*\[}" = "$p]" ]; then n=${l#\[init.svc_debug_pid.}; echo "${n%%\]*}"; break; fi
  done)
  [ -n "$out" ] || out=$(svc_from_rc "$p")
  echo "$out"
}

# process start time in centiseconds since boot (field 22 of /proc/<pid>/stat)
proc_start_cs() {
  local s r
  s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  r=${s##*) }
  set -- $r
  [ -n "${20}" ] || return 1
  echo $(( ${20} * 100 / CLK ))
}

wait_restarted() {  # svc oldpid lib
  local n=0 p
  sleep 3
  while [ $n -lt 30 ]; do
    if [ "$(getprop init.svc.$1)" = running ]; then
      for p in $(lib_pids "$3"); do
        [ "$p" != "$2" ] && { log_line "$1 is back up (pid $p)"; return 0; }
      done
    fi
    n=$((n + 1)); sleep 1
  done
  log_line "WARNING: $1 did not come back within 30s"
  return 1
}

# 0 = every mapping service started after the props; 1 = a restart failed or
# a start time was unreadable; 2 = no process has the library mapped
restart_stale() {  # label lib
  local label="$1" lib="$2" pids pid svc st tried=0 rc=0
  pids=$(lib_pids "$lib")
  [ -n "$pids" ] || { log_line "$label: no process has $lib mapped"; return 2; }
  for pid in $pids; do
    svc=$(svc_for_pid "$pid")
    if [ -z "$svc" ]; then
      log_line "$label: pid $pid maps $lib but no init service found for it; leaving it alone"
      rc=1; continue
    fi
    if echo "$svc" | grep -q -E "^($DENY)$"; then
      log_line "$label: refusing to restart protected service $svc"
      continue
    fi
    st=$(proc_start_cs "$pid") || { log_line "$label: cannot read start time of pid $pid"; rc=1; continue; }
    if [ "$st" -ge "$ARMED" ]; then
      log_line "$label ($svc pid $pid): started after the props were set (ok)"
      continue
    fi
    tried=$((tried + 1))
    [ $tried -gt 3 ] && { log_line "$label: restart limit reached"; break; }
    state "$label ($svc pid $pid) started before the props were set; restarting it once"
    setprop ctl.restart "$svc"
    wait_restarted "$svc" "$pid" "$lib" || rc=1
  done
  return $rc
}

[ -f "$MODDIR/disable" ] && exit 0

ARMED=$(cat "$MODDIR/armed_cs" 2>/dev/null)
if [ -z "$ARMED" ]; then
  state "no armed reference (post-fs-data did not run?)"
  finish
fi

i=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ $i -lt 180 ]; do sleep 2; i=$((i + 2)); done
log_line "boot completed (waited ${i}s)"

restart_stale "sensors HAL" "$HAL_LIB";              A=$?
restart_stale "controller management" "$CMS_LIB";    B=$?

if [ $A -eq 0 ] && [ $B -eq 0 ]; then
  state "armed: props set; sensors HAL and controller management started after them"
else
  state "props set, but service freshness not fully confirmed (HAL=$A CMS=$B); see run.log"
fi
finish
