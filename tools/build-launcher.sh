#!/usr/bin/env bash
# ==============================================================================
# Build Launcher Variants for CleanYourTV
#
# Builds the appropriate APK variant for:
#   - generic-tv  : Native Android TV / Google TV sets (inputs pill enabled)
#   - generic-box : Streaming boxes/dongles (Shield, Chromecast, Onn - inputs pill hidden)
#   - kara        : Fire TV Stick 4K Max 1st Gen & Fire OS 7 devices (API 28, Fire TV settings, bootanim fix)
#   - mantis      : Fire TV Stick 4K 1st Gen & Fire OS 6 devices (API 25, desugaring, Fire TV settings, bootanim fix)
#   - all         : Rebuild all 4 variants
#
# Usage:
#   ./tools/build-launcher.sh [generic-tv | generic-box | kara | mantis | all]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TARGET="${1:-all}"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/Cellar/openjdk@17/17.0.21.0.3/libexec/openjdk.jdk/Contents/Home}"
mkdir -p "$REPO_ROOT/dist"

build_generic_tv() {
    echo "==> Building CleanYourTV Generic TV (Native TV with HDMI Inputs)..."
    (cd "$REPO_ROOT/launcher" && ./gradlew assembleTvRelease -q)
    cp "$REPO_ROOT/launcher/app/build/outputs/apk/tv/release/app-tv-release.apk" "$REPO_ROOT/dist/cleanyourtv-generic-tv.apk"
    echo "✓ Built: dist/cleanyourtv-generic-tv.apk"
}

build_generic_box() {
    echo "==> Building CleanYourTV Generic Box (Streaming Box/Stick without HDMI Inputs)..."
    (cd "$REPO_ROOT/launcher" && ./gradlew assembleBoxRelease -q)
    cp "$REPO_ROOT/launcher/app/build/outputs/apk/box/release/app-box-release.apk" "$REPO_ROOT/dist/cleanyourtv-generic-box.apk"
    echo "✓ Built: dist/cleanyourtv-generic-box.apk"
}

build_kara() {
    echo "==> Building CleanYourTV Kara / Fire OS 7 (API 28, Fire TV Settings, Boot Watchdog Fix)..."
    (cd "$REPO_ROOT/launcher-kara" && ./gradlew assembleRelease -q)
    cp "$REPO_ROOT/launcher-kara/app/build/outputs/apk/release/app-release.apk" "$REPO_ROOT/dist/cleanyourtv-kara.apk"
    mkdir -p "$REPO_ROOT/tools/firetv/bin/fireos7"
    cp "$REPO_ROOT/dist/cleanyourtv-kara.apk" "$REPO_ROOT/tools/firetv/bin/fireos7/cleanyourtv-kara.apk"
    echo "✓ Built: dist/cleanyourtv-kara.apk"
}

build_mantis() {
    echo "==> Building CleanYourTV Mantis / Fire OS 6 (API 25, Desugaring, Fire TV Settings, Boot Watchdog Fix)..."
    (cd "$REPO_ROOT/launcher-mantis" && ./gradlew assembleRelease -q)
    cp "$REPO_ROOT/launcher-mantis/app/build/outputs/apk/release/app-release.apk" "$REPO_ROOT/dist/cleanyourtv-mantis.apk"
    mkdir -p "$REPO_ROOT/tools/firetv/bin/fireos6"
    cp "$REPO_ROOT/dist/cleanyourtv-mantis.apk" "$REPO_ROOT/tools/firetv/bin/fireos6/cleanyourtv-mantis.apk"
    echo "✓ Built: dist/cleanyourtv-mantis.apk"
}

case "$TARGET" in
    generic-tv)
        build_generic_tv
        ;;
    generic-box)
        build_generic_box
        ;;
    kara)
        build_kara
        ;;
    mantis)
        build_mantis
        ;;
    all)
        build_generic_tv
        build_generic_box
        build_kara
        build_mantis
        ;;
    *)
        echo "Unknown target: $TARGET" >&2
        echo "Usage: $0 [generic-tv | generic-box | kara | mantis | all]" >&2
        exit 1
        ;;
esac

echo "=========================================================="
echo " Build completed successfully for: $TARGET"
echo "=========================================================="
