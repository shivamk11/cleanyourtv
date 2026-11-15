#!/usr/bin/env bash
# ==============================================================================
# CleanYourTV Universal Installer
#
# Automatically probes the target device over Wi-Fi ADB and selects the exact
# optimal CleanYourTV launcher build:
#
#   1. Native Android TV / Google TV sets (Sony, TCL, Hisense, Philips)
#      -> cleanyourtv-generic-tv.apk (Inputs tab enabled, standard settings)
#
#   2. Streaming Boxes & HDMI Dongles (Shield TV, Chromecast, Onn Box, Mi Box)
#      -> cleanyourtv-generic-box.apk (Inputs tab hidden, standard settings)
#
#   3. Amazon Fire TV Stick 4K Max 1st Gen & Fire OS 7 devices (kara, sheldon)
#      -> cleanyourtv-kara.apk (Inputs hidden, Fire TV Settings, bootanim fix, API 28)
#
#   4. Amazon Fire TV Stick 4K 1st Gen & Fire OS 6 devices (mantis)
#      -> cleanyourtv-mantis.apk (Inputs hidden, Fire TV Settings, bootanim fix, API 25 + desugaring)
#
# Fire TV specific modifications (GhostLock, HomeActivity_vNext disabling,
# bootanim.real_home_ready, OTA neutralization) are strictly isolated and NEVER
# executed on standard Android TV / Google TV devices.
#
# Usage:
#   ./tools/install.sh <TV_IP_ADDRESS>
#   ./tools/install.sh 192.168.1.50
# ==============================================================================

set -euo pipefail

export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

if [ $# -lt 1 ]; then
    echo "Usage: $0 <TV_IP_ADDRESS> [options]"
    echo "Example: $0 192.168.1.50"
    exit 1
fi

TV_HOST="$1"
case "$TV_HOST" in
    *:*) TARGET="$TV_HOST" ;;
    *)   TARGET="${TV_HOST}:5555" ;;
esac

echo "=========================================================="
echo " CleanYourTV Universal Device Probe & Installation"
echo " Target: $TARGET"
echo "=========================================================="

if ! command -v adb >/dev/null 2>&1; then
    echo "ERROR: 'adb' command not found. Please install Android Platform Tools." >&2
    exit 1
fi

# 1. Connect over Wi-Fi ADB
echo "[1/4] Connecting to target device over Wi-Fi ADB..."
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
    echo "Make sure the TV/device is turned ON, awake, on the same Wi-Fi, and ADB debugging is enabled." >&2
    exit 1
fi

# 2. Comprehensive Device Hardware & OS Probing
echo "[2/4] Probing device architecture, form factor, and OS capabilities..."

BRAND=$(adb -s "$TARGET" shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
MANUFACTURER=$(adb -s "$TARGET" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
MODEL=$(adb -s "$TARGET" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
BOARD=$(adb -s "$TARGET" shell getprop ro.product.name 2>/dev/null | tr -d '\r')
SDK=$(adb -s "$TARGET" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
OS_NAME=$(adb -s "$TARGET" shell getprop ro.build.version.name 2>/dev/null | tr -d '\r')
CHARACTERISTICS=$(adb -s "$TARGET" shell getprop ro.build.characteristics 2>/dev/null | tr -d '\r')

echo "  - Device:          $BRAND $MODEL ($BOARD)"
echo "  - Manufacturer:    $MANUFACTURER"
echo "  - Android API:     $SDK"
echo "  - OS Name:         ${OS_NAME:-Android}"
echo "  - Characteristics: $CHARACTERISTICS"

# Detect Amazon Fire TV
IS_FIRETV=0
if [ "$BRAND" = "Amazon" ] || [ "$MANUFACTURER" = "Amazon" ] || echo "$OS_NAME" | grep -qi "Fire OS"; then
    IS_FIRETV=1
fi

# Detect whether Inputs Tab is needed (Streaming boxes vs Native TV sets)
NEEDS_INPUTS=0
if [ "$IS_FIRETV" -eq 1 ]; then
    # Fire TV sticks and streaming dongles have no physical HDMI inputs
    NEEDS_INPUTS=0
else
    case "$CHARACTERISTICS" in
        *box*|*dongle*|*stick*)
            NEEDS_INPUTS=0
            ;;
        *)
            # Query TvInputManager for physical hardware inputs (HDMI ports, Tuner, AV)
            HW_INPUTS=$(adb -s "$TARGET" shell "dumpsys tv_input 2>/dev/null | grep -iE 'hardware: true|type=HDMI|type=TUNER|type=DVI' || true")
            if [ -n "$HW_INPUTS" ]; then
                NEEDS_INPUTS=1
            else
                NEEDS_INPUTS=0
            fi
            ;;
    esac
fi

# 3. Select Target Variant
echo "[3/4] Selecting optimal launcher variant..."
if [ "$IS_FIRETV" -eq 1 ]; then
    if [ "$BOARD" = "mantis" ] || [ "$SDK" -le 25 ]; then
        VARIANT="mantis"
        APK="$REPO_ROOT/dist/cleanyourtv-mantis.apk"
        BUILD_DIR="$REPO_ROOT/launcher-mantis"
        DESC="Fire TV Stick 4K (Fire OS 6 / API 25 with desugaring, 60s boot fix, Fire TV settings, no inputs)"
    else
        VARIANT="kara"
        APK="$REPO_ROOT/dist/cleanyourtv-kara.apk"
        BUILD_DIR="$REPO_ROOT/launcher-kara"
        DESC="Fire TV Stick 4K Max / Lite (Fire OS 7+ / API 28+ with 60s boot fix, Fire TV settings, no inputs)"
    fi
else
    if [ "$NEEDS_INPUTS" -eq 1 ]; then
        VARIANT="generic-tv"
        APK="$REPO_ROOT/dist/cleanyourtv-generic-tv.apk"
        BUILD_DIR="$REPO_ROOT/launcher"
        DESC="Native Android TV / Google TV (Inputs tab enabled, standard OEM settings)"
    else
        VARIANT="generic-box"
        APK="$REPO_ROOT/dist/cleanyourtv-generic-box.apk"
        BUILD_DIR="$REPO_ROOT/launcher"
        DESC="Streaming Box / Dongle (Inputs tab hidden, standard Android TV settings)"
    fi
fi

echo "  -> Selected Variant: $VARIANT"
echo "  -> Description:      $DESC"
echo "  -> APK Path:         $APK"

# Ensure APK exists or build it
if [ ! -f "$APK" ]; then
    echo "APK not found at $APK. Building variant from source..."
    "$SCRIPT_DIR/build-launcher.sh" "$VARIANT"
fi

# 4. Device Installation Pipeline
echo "[4/4] Deploying CleanYourTV launcher..."

if [ "$IS_FIRETV" -eq 1 ]; then
    echo "=========================================================="
    echo " Delegating to specialized Fire TV setup toolchain..."
    echo "=========================================================="
    exec "$SCRIPT_DIR/firetv/setup.sh" "$TARGET"
else
    echo "Deploying on standard Android TV / Google TV device..."
    echo "  (Fire TV specific hacks and root exploits are SKIPPED)"

    # Stream install APK
    echo "Installing launcher package..."
    adb -s "$TARGET" install -r "$APK"

    # Grant permissions and compile
    echo "Optimizing bytecode..."
    adb -s "$TARGET" shell "pm grant com.gathin.tvhome android.permission.WRITE_SECURE_SETTINGS 2>/dev/null || true"
    adb -s "$TARGET" shell "cmd package compile -m speed -f com.gathin.tvhome 2>/dev/null || true"

    # Set default Home activity
    echo "Setting CleanYourTV as default Home activity..."
    adb -s "$TARGET" shell "cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity 2>/dev/null || true"

    # Start CleanYourTV
    echo "Starting CleanYourTV..."
    adb -s "$TARGET" shell "am start -n com.gathin.tvhome/.MainActivity" >/dev/null 2>&1 || true
    adb -s "$TARGET" shell "input keyevent 3" >/dev/null 2>&1 || true

    echo "=========================================================="
    echo " Installation complete on $TARGET ($VARIANT)!"
    echo " Press Home on your remote to view CleanYourTV."
    echo "=========================================================="
fi
