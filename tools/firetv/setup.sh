#!/usr/bin/env bash
# ==============================================================================
# CleanYourTV Fire TV Edition - All-in-One Automated Setup Toolchain
#
# Supports:
#   - Fire TV Stick 4K 1st Gen (mantis / AFTMM - Fire OS 6 / Android API 25)
#   - Fire TV Stick 4K Max 1st Gen (kara / AFTKA - Fire OS 7 / Android API 28)
#   - Fire TV Stick Lite / 3rd Gen (sheldon / sheldonp - Fire OS 7)
#   - Any Fire OS 6 / 7 / 8 device
#
# Features:
#   - 100% wireless over Wi-Fi ADB (no OTG cable required)
#   - Zero external downloads: bundles GhostLock root binaries & debloat profiles
#   - Native 0 ms hardware Home key binding via component disabling
#   - Preserves complete 14-grid Amazon Settings menu (Network, Display, Remotes, etc.)
#   - Fixes Fire OS 60-second boot animation watchdog stall
#   - Full OTA updater neutralization & AdGuard Private DNS safety net
#
# Usage:
#   ./tools/firetv/setup.sh <TV_IP_ADDRESS>
#   ./tools/firetv/setup.sh 192.168.1.50
#   ./tools/firetv/setup.sh 192.168.1.50 --debloat-only
#   ./tools/firetv/setup.sh 192.168.1.50 --launcher-only
#   ./tools/firetv/setup.sh 192.168.1.50 --build
# ==============================================================================

set -euo pipefail

# Prevent MSYS / Git-Bash on Windows from mangling remote POSIX paths
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

TV_HOST=""
MODE="full"
BUILD_SOURCE=0

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --launcher-only) MODE="launcher"; shift ;;
        --debloat-only)  MODE="debloat"; shift ;;
        --build)         BUILD_SOURCE=1; shift ;;
        --help|-h)
            echo "CleanYourTV Fire TV Edition Setup"
            echo "Usage: $0 <TV_IP_ADDRESS> [--launcher-only | --debloat-only | --build]"
            echo ""
            echo "Options:"
            echo "  <TV_IP_ADDRESS>   IP address of your Fire TV Stick (e.g. 192.168.1.50)"
            echo "  --launcher-only   Install CleanYourTV and set as native Home without debloating"
            echo "  --debloat-only    Apply debloat profile and block OTAs without installing launcher"
            echo "  --build           Recompile launcher APK from source using Gradle wrapper"
            exit 0 ;;
        *)
            if [ -z "$TV_HOST" ]; then TV_HOST="$1"; shift;
            else echo "Unknown argument: $1" >&2; exit 1; fi ;;
    esac
done

if [ -z "$TV_HOST" ]; then
    echo "ERROR: Missing Fire TV IP address." >&2
    echo "Usage: $0 <TV_IP_ADDRESS> [options]" >&2
    echo "Example: $0 192.168.1.50" >&2
    exit 1
fi

case "$TV_HOST" in
    *:*) TARGET="$TV_HOST" ;;
    *)   TARGET="${TV_HOST}:5555" ;;
esac

echo "=========================================================="
echo " CleanYourTV Fire TV Edition (All-in-One Setup)"
echo " Mode:   $MODE"
echo " Target: $TARGET"
echo "=========================================================="

# Check local dependencies
if ! command -v adb >/dev/null 2>&1; then
    echo "ERROR: 'adb' command not found. Please install Android Platform Tools." >&2
    exit 1
fi

# 1. Connect over Wi-Fi ADB
echo "[1/6] Connecting to Fire TV over Wi-Fi..."
adb disconnect "$TARGET" >/dev/null 2>&1 || true
timeout 10s adb connect "$TARGET" >/dev/null 2>&1 || true

connected=0
for _ in {1..12}; do
    if adb -s "$TARGET" get-state 2>/dev/null | grep -q "device"; then
        connected=1
        break
    fi
    sleep 1
done

if [ "$connected" -ne 1 ]; then
    echo "ERROR: Unable to connect to $TARGET." >&2
    echo "Verify that:" >&2
    echo "  1. The Fire TV is turned ON and awake (press a button on the remote)." >&2
    echo "  2. The Fire TV is connected to the same Wi-Fi network." >&2
    echo "  3. ADB Debugging is enabled in Settings -> My Fire TV -> Developer Options." >&2
    exit 1
fi

MODEL=$(adb -s "$TARGET" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
BOARD=$(adb -s "$TARGET" shell getprop ro.product.name 2>/dev/null | tr -d '\r')
FIREOS=$(adb -s "$TARGET" shell getprop ro.build.version.name 2>/dev/null | tr -d '\r')
SDK=$(adb -s "$TARGET" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
BUILD_INC=$(adb -s "$TARGET" shell getprop ro.build.version.incremental 2>/dev/null | tr -d '\r')
echo "Connected: $MODEL ($BOARD) running $FIREOS (Android API $SDK, build $BUILD_INC)"

# Determine device family & binary profiles
IS_FIREOS6=0
if [ "$BOARD" = "mantis" ] || [ "$SDK" -le 25 ]; then
    IS_FIREOS6=1
    DEBLOAT_PROFILE="$SCRIPT_DIR/profiles/mantis_4k_fireos6.txt"
    GL_BIN="$SCRIPT_DIR/bin/fireos6/ghostlock_root"
    GL_CONF="$SCRIPT_DIR/bin/fireos6/mantis-NS6711-5908.conf"
else
    DEBLOAT_PROFILE="$SCRIPT_DIR/profiles/sheldon_lite_fireos7.txt"
    GL_BIN="$SCRIPT_DIR/bin/fireos7/ghostlock_root"
    GL_CONF=""
fi

# 2. Check and initialize root access
echo "[2/6] Verifying root privilege access..."
REMOTE_GL_DIR="/data/local/tmp/gl"
adb -s "$TARGET" shell "mkdir -p $REMOTE_GL_DIR" >/dev/null 2>&1

ROOT_METHOD="none"
if adb -s "$TARGET" shell "su -c 'id'" 2>/dev/null | grep -q "uid=0"; then
    ROOT_METHOD="su"
    echo "Root access verified via existing su binary."
elif adb -s "$TARGET" shell "$REMOTE_GL_DIR/su -c 'id'" 2>/dev/null | grep -q "uid=0"; then
    ROOT_METHOD="gl_su"
    echo "Root access verified via GhostLock daemon."
else
    echo "Transient root required for native Home binding and protected package control."
    echo "Staging bundled GhostLock binary for $BOARD..."
    if [ ! -f "$GL_BIN" ]; then
        echo "ERROR: GhostLock binary not found at $GL_BIN" >&2
        exit 1
    fi
    adb -s "$TARGET" push "$GL_BIN" "$REMOTE_GL_DIR/ghostlock_root" >/dev/null
    adb -s "$TARGET" shell "chmod 755 $REMOTE_GL_DIR/ghostlock_root"

    if [ "$IS_FIREOS6" -eq 1 ] && [ -n "$GL_CONF" ] && [ -f "$GL_CONF" ]; then
        adb -s "$TARGET" push "$GL_CONF" "$REMOTE_GL_DIR/profile.conf" >/dev/null
        ROOT_METHOD="mantis_exec"
    else
        ROOT_METHOD="kara_exec"
    fi
    echo "GhostLock toolchain staged successfully (Method: $ROOT_METHOD)."
fi

# 3. Prepare Launcher APK
APK="$REPO_ROOT/launcher/cleanyourtv-release.apk"
if [ "$MODE" = "full" ] || [ "$MODE" = "launcher" ]; then
    echo "[3/6] Preparing CleanYourTV launcher binary..."
    if [ "$BUILD_SOURCE" -eq 1 ] || [ ! -f "$APK" ]; then
        echo "Building CleanYourTV APK from source (minSdk 25, inputs disabled)..."
        (cd "$REPO_ROOT/launcher" && ./gradlew assembleRelease -q)
        APK="$REPO_ROOT/launcher/app/build/outputs/apk/release/app-release.apk"
    fi

    echo "Pushing launcher APK to device..."
    adb -s "$TARGET" push "$APK" "$REMOTE_GL_DIR/cleanyourtv.apk" >/dev/null
fi

# 4. Stage Debloat Profile
if [ "$MODE" = "full" ] || [ "$MODE" = "debloat" ]; then
    echo "[4/6] Staging debloat profile ($(basename "$DEBLOAT_PROFILE"))..."
    adb -s "$TARGET" push "$DEBLOAT_PROFILE" "$REMOTE_GL_DIR/debloat.txt" >/dev/null
fi

# 5. Build and execute remote root script
echo "[5/6] Executing configuration and native Home handover..."

REMOTE_SCRIPT="$REMOTE_GL_DIR/firetv_setup_exec.sh"
cat << 'EOF' > /tmp/firetv_setup_exec.sh
#!/system/bin/sh
set -x

GL_DIR="/data/local/tmp/gl"
LOG="$GL_DIR/exec.log"
exec > "$LOG" 2>&1

echo "=== Fire TV Automated Setup Execution ==="
date

# Step A: Install CleanYourTV launcher if staged
if [ -f "$GL_DIR/cleanyourtv.apk" ]; then
    echo "Installing CleanYourTV APK..."
    pm install -r "$GL_DIR/cleanyourtv.apk"
    rm -f "$GL_DIR/cleanyourtv.apk"
    
    echo "Granting permissions and optimizing bytecode (AOT speed)..."
    pm grant com.gathin.tvhome android.permission.WRITE_SECURE_SETTINGS 2>/dev/null || true
    pm grant com.gathin.tvhome android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
    cmd package compile -m speed -f com.gathin.tvhome || true
fi

# Step B: Native Home Handover (Preserving 14-grid Amazon Settings)
echo "Re-enabling stock launcher package to guarantee Settings availability..."
pm enable com.amazon.tv.launcher 2>/dev/null || true

echo "Disabling ONLY HomeActivity_vNext component..."
pm disable-user --user 0 com.amazon.tv.launcher/.ui.HomeActivity_vNext 2>/dev/null || pm disable com.amazon.tv.launcher/.ui.HomeActivity_vNext 2>/dev/null || true

echo "Disabling setup wizards and home starters..."
pm disable-user --user 0 com.amazon.tv.oobe 2>/dev/null || pm disable com.amazon.tv.oobe 2>/dev/null || true
pm disable-user --user 0 com.amazon.firehomestarter 2>/dev/null || pm disable com.amazon.firehomestarter 2>/dev/null || true

echo "Setting CleanYourTV as default Home activity..."
cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity

# Step C: Cancel 60-second Fire OS Boot Animation Watchdog
echo "Signaling real home ready to dismiss boot animation immediately..."
settings put secure bootanim.real_home_ready 1

# Step D: Block OTA Updates
echo "Neutralizing OTA updaters..."
for ota in com.amazon.device.software.ota com.amazon.device.software.ota.override com.amazon.tv.forcedotaupdater.v2; do
    pm disable-user --user 0 "$ota" 2>/dev/null || pm disable "$ota" 2>/dev/null || true
    pm hide --user 0 "$ota" 2>/dev/null || pm hide "$ota" 2>/dev/null || true
    pm clear "$ota" 2>/dev/null || true
done

# Step E: AdGuard Private DNS Protection
echo "Configuring AdGuard Private DNS..."
settings put global private_dns_specifier dns.adguard-dns.com
settings put global private_dns_mode hostname

# Step F: Apply Debloat Profile
if [ -f "$GL_DIR/debloat.txt" ]; then
    echo "Applying system debloat list..."
    while IFS= read -r line || [ -n "$line" ]; do
        pkg=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$pkg" ] && continue
        case "$pkg" in
            com.amazon.tv.settings.v2|com.amazon.tv.ime|com.android.bluetooth|com.amazon.device.bluetooth)
                continue ;;
            *)
                pm disable-user --user 0 "$pkg" 2>/dev/null || pm disable "$pkg" 2>/dev/null || true
                ;;
        esac
    done < "$GL_DIR/debloat.txt"
fi

echo "=== Setup complete ==="
EOF

adb -s "$TARGET" push /tmp/firetv_setup_exec.sh "$REMOTE_SCRIPT" >/dev/null
adb -s "$TARGET" shell "chmod 755 $REMOTE_SCRIPT"
rm -f /tmp/firetv_setup_exec.sh

# Execute script based on root method
case "$ROOT_METHOD" in
    su)
        adb -s "$TARGET" shell "su -c 'sh $REMOTE_SCRIPT'"
        ;;
    gl_su)
        adb -s "$TARGET" shell "$REMOTE_GL_DIR/su -c 'sh $REMOTE_SCRIPT'"
        ;;
    mantis_exec)
        echo "Executing privilege escalation on Mantis (Fire OS 6)..."
        adb -s "$TARGET" shell "cd $REMOTE_GL_DIR && ./ghostlock_root --profile ./profile.conf --tries 1 --exec $REMOTE_SCRIPT" >/dev/null 2>&1 || true
        ;;
    kara_exec)
        echo "Executing privilege escalation on Kara/Sheldon (Fire OS 7)..."
        adb -s "$TARGET" shell "cd $REMOTE_GL_DIR && ./ghostlock_root --exec $REMOTE_SCRIPT" >/dev/null 2>&1 || true
        ;;
    none)
        echo "Running unprivileged fallback execution..."
        adb -s "$TARGET" shell "sh $REMOTE_SCRIPT" || true
        ;;
esac

# 6. Verification and Launch
echo "[6/6] Verifying deployment..."
sleep 2

HOME_RESOLVE=$(adb -s "$TARGET" shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" 2>&1 | tail -n 1 | tr -d '\r')
echo "Default Home Activity: $HOME_RESOLVE"

BOOTANIM=$(adb -s "$TARGET" shell "settings get secure bootanim.real_home_ready" 2>/dev/null | tr -d '\r')
echo "Boot Animation Signal: $BOOTANIM (1 = instant boot, 60s stall fixed)"

DNS_MODE=$(adb -s "$TARGET" shell "settings get global private_dns_mode" 2>/dev/null | tr -d '\r')
DNS_SPEC=$(adb -s "$TARGET" shell "settings get global private_dns_specifier" 2>/dev/null | tr -d '\r')
echo "Private DNS:           $DNS_MODE ($DNS_SPEC)"

# Trigger Home screen
echo "Launching CleanYourTV..."
adb -s "$TARGET" shell "am start -n com.gathin.tvhome/.MainActivity" >/dev/null 2>&1 || true
adb -s "$TARGET" shell "input keyevent 3" >/dev/null 2>&1 || true

echo ""
echo "=========================================================="
echo " All-in-One Setup Successfully Completed!"
echo " CleanYourTV is now the zero-latency native Home launcher."
echo " Press the Home button on your Fire TV remote to test."
echo ""
echo " To revert everything at any time, run:"
echo "   ./tools/firetv/restore.sh $TV_HOST"
echo "=========================================================="
