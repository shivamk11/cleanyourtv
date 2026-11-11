#!/usr/bin/env bash
# ==============================================================================
# CleanYourTV Fire TV Edition - Restore Script
#
# Reverts debloat, re-enables stock Amazon launcher & components, unhides OTA
# updaters, and resets DNS back to stock default.
#
# Usage:
#   ./tools/firetv/restore.sh <TV_IP_ADDRESS>
#   ./tools/firetv/restore.sh 192.168.1.50
# ==============================================================================

set -euo pipefail

export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ $# -lt 1 ]; then
    echo "CleanYourTV Fire TV Restore Tool"
    echo "Usage: $0 <TV_IP_ADDRESS>"
    echo "Example: $0 192.168.1.50"
    exit 1
fi

TV_HOST="$1"
case "$TV_HOST" in
    *:*) TARGET="$TV_HOST" ;;
    *)   TARGET="${TV_HOST}:5555" ;;
esac

echo "=========================================================="
echo " Restoring stock configuration on $TARGET"
echo "=========================================================="

adb connect "$TARGET" >/dev/null 2>&1 || true

exec_root() {
    local cmd="$1"
    if adb -s "$TARGET" shell "/data/local/tmp/gl/su -c 'id'" 2>/dev/null | grep -q "uid=0"; then
        adb -s "$TARGET" shell "/data/local/tmp/gl/su -c '$cmd'"
    elif adb -s "$TARGET" shell "su -c 'id'" 2>/dev/null | grep -q "uid=0"; then
        adb -s "$TARGET" shell "su -c '$cmd'"
    else
        adb -s "$TARGET" shell "$cmd"
    fi
}

echo "1. Re-enabling stock Amazon launcher and Home activity..."
exec_root "pm enable com.amazon.tv.launcher"
exec_root "pm enable com.amazon.tv.launcher/.ui.HomeActivity_vNext"
exec_root "pm enable com.amazon.tv.oobe || true"
exec_root "pm enable com.amazon.firehomestarter || true"

echo "2. Re-setting stock launcher as default Home..."
exec_root "cmd package set-home-activity --user 0 com.amazon.tv.launcher/.ui.HomeActivity_vNext" || true

echo "3. Unhiding and re-enabling OTA updaters..."
for ota in com.amazon.device.software.ota com.amazon.device.software.ota.override com.amazon.tv.forcedotaupdater.v2; do
    exec_root "pm unhide --user 0 $ota || true"
    exec_root "pm enable --user 0 $ota || true"
done

echo "4. Resetting Private DNS to default..."
adb -s "$TARGET" shell "settings put global private_dns_mode off" 2>/dev/null || true

echo "5. Restoring debloated packages..."
for profile in "$SCRIPT_DIR"/profiles/*.txt; do
    [ -f "$profile" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
        pkg=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$pkg" ] && continue
        exec_root "pm enable $pkg || pm unhide --user 0 $pkg || true" >/dev/null 2>&1 || true
    done < "$profile"
done

echo "6. Launching stock Home screen..."
adb -s "$TARGET" shell "am start -a android.intent.action.MAIN -c android.intent.category.HOME" >/dev/null 2>&1 || true
adb -s "$TARGET" shell "input keyevent 3" >/dev/null 2>&1 || true

echo "=========================================================="
echo " Restore complete! Stock Amazon home screen and services restored."
echo "=========================================================="
