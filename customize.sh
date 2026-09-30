#!/system/bin/sh
# Install-time checks only. Nothing is patched and no system files are touched.

say()  { ui_print "  $1"; }
line() { ui_print "=================================================="; }

line
ui_print "  Touch Plus (RUBYPRQ) on Quest 2"
line

DEV=$(getprop ro.product.device)
if [ "$DEV" != "hollywood" ]; then
  say "[!!] This module is for Quest 2 (hollywood) only; found '$DEV'."
  abort
fi
say "[ok] Device is Quest 2 (hollywood)"

BUILD=$(getprop ro.build.version.incremental)
say "[ok] Firmware build $BUILD"

HAL=/odm/lib64/libsyncboss.so
if [ -f "$HAL" ] && grep -q disable_fw_version_check "$HAL" 2>/dev/null; then
  say "[ok] sensors HAL reads disable_fw_version_check"
else
  say "[..] could not confirm the sensors HAL reads disable_fw_version_check"
fi

CMS=$(find /system /system_ext /vendor /odm /product -maxdepth 4 -name libcmsservice-headset.so 2>/dev/null | head -1)
if [ -n "$CMS" ] && grep -q skipctrlfwupdate "$CMS" 2>/dev/null; then
  say "[ok] controller management reads skipctrlfwupdate ($CMS)"
else
  say "[..] could not confirm controller management reads skipctrlfwupdate"
fi

echo "$BUILD" > "$MODPATH/build_id"

set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

line
say "Props are set at boot, memory-only (resetprop -n)."
say "No partition, overlay or vbmeta changes."
say "Removing the module restores stock on the next boot."
say "If the firmware build changes, the module disables itself."
say "Reboot to activate. Log: /data/adb/modules/rubyprq_on_q2/run.log"
line
