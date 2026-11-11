# Amazon Fire TV Edition: All-in-One Native Launcher, Debloat & Setup Guide

This guide details the complete, self-contained setup for running **CleanYourTV** as the **native, default Home launcher** with **0 ms hardware Home button latency** on Amazon Fire TV Sticks. 

Everything needed—including pre-built GhostLock root binaries, debloat profiles, and automated wireless setup scripts—is bundled directly in this repository. **No external downloads, companion repositories, or OTG hardware cables are required.**

---

## 1. Supported Devices & Architecture Overview

| Property | Fire TV Stick 4K 1st Gen | Fire TV Stick 4K Max 1st Gen | Fire TV Stick Lite / 3rd Gen |
| :--- | :--- | :--- | :--- |
| **Model / Board** | `AFTMM` (`mantis`) | `AFTKA` (`kara`) | `AFTSS` / `AFTSSS` (`sheldon` / `sheldonp`) |
| **Chipset** | MediaTek MT8695 | MediaTek MT8696 | MediaTek MT8695D |
| **Kernel / Arch** | Linux 4.4.120+ (`armv7l`) | Linux 4.19 (`arm64` kernel, 32-bit user) | Linux 4.9 (`armv7l`) |
| **Fire OS** | Fire OS **6.7.1.1** (Android 7.1.2 / API 25) | Fire OS **7.7.1.3** (Android 9 / API 28) | Fire OS **7.x** (Android 9 / API 28) |
| **Root Engine** | Bundled GhostLock API 24 (`tools/firetv/bin/fireos6/`) | Bundled GhostLock API 28 (`tools/firetv/bin/fireos7/`) | Bundled GhostLock API 28 (`tools/firetv/bin/fireos7/`) |
| **Connection** | **100% Wireless Wi-Fi ADB** (`<TV_IP>:5555`) | **100% Wireless Wi-Fi ADB** (`<TV_IP>:5555`) | **100% Wireless Wi-Fi ADB** (`<TV_IP>:5555`) |

---

## 2. Quick Start: Automated Wireless One-Line Setup

Ensure ADB debugging is enabled on your Fire TV (`Settings` -> `My Fire TV` -> `Developer Options` -> `ADB Debugging = ON`), then run from your terminal:

```bash
# Automated Full Setup: Root -> Debloat -> Install Launcher -> Bind Home -> Block OTAs -> DNS
./tools/firetv/setup.sh <TV_IP_ADDRESS>

# Example:
./tools/firetv/setup.sh 192.168.1.50
```

The script automatically:
1. Connects to the Fire TV over Wi-Fi ADB.
2. Identifies the board (`mantis`, `kara`, `sheldon`) and Fire OS version.
3. Automatically selects and deploys the appropriate bundled GhostLock root binary.
4. Safely debloats background telemetry, ads, and recommendation daemons.
5. Installs CleanYourTV and sets it as the native default Home activity.
6. Fixes the 60-second Fire OS boot animation watchdog delay.
7. Blocks OTA software updates via package neutralization and AdGuard Private DNS.

### Custom Flags
```bash
# Install launcher and set native Home only (keep stock services)
./tools/firetv/setup.sh 192.168.1.50 --launcher-only

# Apply debloat profile and block OTAs only (without installing custom launcher)
./tools/firetv/setup.sh 192.168.1.50 --debloat-only

# Recompile the launcher APK from source before deploying
./tools/firetv/setup.sh 192.168.1.50 --build
```

### Complete Rollback
To restore the stock Amazon launcher and re-enable all original services at any time:
```bash
./tools/firetv/restore.sh <TV_IP_ADDRESS>
```

---

## 3. How Native Home Binding Works (0 ms Latency)

### The Flaw of Accessibility Wrappers
Third-party launcher apps historically used an Android Accessibility Service (`HomeKeyService`) or background polling to detect when Amazon's launcher appears and simulate a quick app switch.
- **500–1500 ms latency** every time the Home button is pressed.
- **Visual flicker:** The Amazon home screen renders briefly before switching.
- **Service termination:** Fire OS kills accessibility services during 4K HDR playback to free RAM.

### The Component-Level Solution
Instead of disabling the entire `com.amazon.tv.launcher` package, we disable **ONLY** the internal Home activity component:
```bash
pm disable com.amazon.tv.launcher/.ui.HomeActivity_vNext
cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity
```
Because the parent package `com.amazon.tv.launcher` remains enabled:
1. **Zero Latency:** Fire OS WindowManager routes the hardware Home key directly to CleanYourTV with 0 ms delay.
2. **Full 14-Grid Settings Access:** Fire OS's complete settings hub (`com.amazon.tv.launcher/.ui.MainSettingsActivity`) remains 100% accessible via the Settings icon (Network, Display & Audio, Remotes & Bluetooth, Equipment Control, Notifications, Preferences, Alexa, etc.).
3. **No Interception Services:** No background daemon or accessibility service needs to run.

---

## 4. Understanding the Wireless Root Mechanism

Fire OS restricts package management commands (`pm disable`, `pm hide`) on Amazon system apps from the standard unprivileged ADB shell (`uid=2000`). Transient in-memory root is used during setup to configure package states.

All required exploit binaries and configuration profiles are pre-compiled and bundled inside `tools/firetv/bin/`:

### A. Fire OS 6 (`mantis` / Fire TV Stick 4K 1st Gen)
- **Target Architecture:** MediaTek MT8695, 32-bit ARM kernel (4.4.120+), Android 7.1.2 (API 25).
- **Bundled Files:**
  - Binary: `tools/firetv/bin/fireos6/ghostlock_root` (built against API 24 libc)
  - Profile: `tools/firetv/bin/fireos6/mantis-NS6711-5908.conf`
- **Mechanism:** Exploits kernel memory via IPv4 stream socket stack-stamping with profile-driven task and credential structure offsets.
- **Execution Mode:** Exec-only transient execution (`--profile <conf> --exec <script>`). It does not install persistent root or alter SELinux. It runs the setup script as UID 0 and exits cleanly.

### B. Fire OS 7 (`kara` / 4K Max 1st Gen & `sheldon` / Lite / 3rd Gen)
- **Target Architecture:** MediaTek MT8696 / MT8695D, 64-bit kernel with 32-bit userland, Android 9 (API 28).
- **Bundled Files:**
  - Binary: `tools/firetv/bin/fireos7/ghostlock_root` (built against API 28 libc with embedded multi-build profiles)
- **Mechanism:** Exploits `IonStack` futex-PI UAF (`configfs-mm-reclaim-v1`) to gain kernel RW and patch task credentials to UID 0.
- **Execution Mode:** Runs either transiently via `--exec <script>` or via lightweight local root socket daemon (`/data/local/tmp/gl/su`).

---

## 5. Eliminating the 60-Second Boot Animation Stall

### Root Cause
Analysis of the Fire OS WindowManager service (`fosservices.odex`) revealed:
```text
FireTvWindowManagerServiceCallback$HomeInitialisationObserver
```
Fire OS listens for a signal on the secure setting:
```text
bootanim.real_home_ready
```
When Amazon's stock home screen finishes loading, it writes `1` to this setting, signaling `surfaceflinger` to dismiss the boot animation.

When `HomeActivity_vNext` is disabled, the stock home screen never loads, so this signal is never sent. Fire OS enters a hardcoded **60-second fallback watchdog timer** (`BOOT_ANIMATION_TIMEOUT = 60000`):
```text
FireTvWmsCallback: Stopping boot animation because timer elapsed waiting for real home to send signal.
```
This caused the TV to stay stuck on the boot logo for over 88 seconds, even though Android finished loading in 28 seconds.

### The CleanYourTV Solution
CleanYourTV automatically writes `bootanim.real_home_ready = 1` inside `MainActivity.onCreate()` and `onResume()`:
```java
private void dismissFireTvBootAnimation() {
    try {
        android.provider.Settings.Secure.putInt(getContentResolver(), "bootanim.real_home_ready", 1);
    } catch (Throwable ignored) {}
}
```
With `WRITE_SECURE_SETTINGS` granted, the boot animation exits the instant CleanYourTV loads:
- **Before:** ~88.2 seconds trapped on boot logo.
- **After:** **~14.9s** on 4K Max / **~30.8s** on 4K 1st Gen.
- **Improvement:** Boot animation dismissed **57 seconds faster**.

---

## 6. Fire TV Stick UI Customizations

### Clean Top Bar (Inputs Pill Removed)
Fire TV Sticks are HDMI sources that plug into TVs; they are not displays with multiple HDMI inputs. CleanYourTV Fire TV Edition sets `<bool name="show_inputs_pill">false</bool>` in `launcher/app/src/main/res/values/config.xml`, removing the unused "Inputs" pill from the top navigation bar.

### API 25 Compatibility & Core Library Desugaring
Upstream CleanYourTV targets Android API 26+. To support Fire OS 6 (`mantis`, Android 7.1.2 / API 25), the launcher is compiled with:
- `minSdk 25`
- Java 8 API desugaring (`coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"`)
- SDK version checks for API 26+ methods (e.g. `PackageManager.getChangedPackages()`).

---

## 7. Dual-Layer OTA Update Blocking

Amazon frequently pushes background updates that attempt to restore stock launcher components. The toolchain implements a dual-layer defense:

1. **Package Layer:** Disables, hides, and clears update packages:
   - `com.amazon.device.software.ota`
   - `com.amazon.device.software.ota.override`
   - `com.amazon.tv.forcedotaupdater.v2`
2. **DNS Layer:** Enforces encrypted Private DNS:
   - Sets `private_dns_mode` to `hostname`
   - Sets `private_dns_specifier` to `dns.adguard-dns.com`
   This blocks all outbound requests to Amazon's firmware update CDN (`amzdigitaldownloads.edgesuite.net`, `softwareupdates.amazon.com`).

---

## 8. Manual Step-by-Step Instructions

For advanced users who prefer executing commands manually:

### Step 1: Connect and Push Assets
```bash
adb connect <TV_IP>:5555
adb -s <TV_IP>:5555 shell "mkdir -p /data/local/tmp/gl"

# Push launcher APK
adb -s <TV_IP>:5555 push launcher/cleanyourtv-release.apk /data/local/tmp/gl/cleanyourtv.apk

# Push root binary (select matching version)
# For Fire OS 6 (mantis):
adb -s <TV_IP>:5555 push tools/firetv/bin/fireos6/ghostlock_root /data/local/tmp/gl/
adb -s <TV_IP>:5555 push tools/firetv/bin/fireos6/mantis-NS6711-5908.conf /data/local/tmp/gl/
# For Fire OS 7 (kara / sheldon):
adb -s <TV_IP>:5555 push tools/firetv/bin/fireos7/ghostlock_root /data/local/tmp/gl/

adb -s <TV_IP>:5555 shell "chmod 755 /data/local/tmp/gl/ghostlock_root"
```

### Step 2: Install Launcher & Grant Permissions
```bash
adb -s <TV_IP>:5555 shell "pm install -r /data/local/tmp/gl/cleanyourtv.apk"
adb -s <TV_IP>:5555 shell "pm grant com.gathin.tvhome android.permission.WRITE_SECURE_SETTINGS"
adb -s <TV_IP>:5555 shell "cmd package compile -m speed -f com.gathin.tvhome"
```

### Step 3: Execute Root Handover
Create `/data/local/tmp/gl/handover.sh`:
```bash
adb -s <TV_IP>:5555 shell "cat << 'EOF' > /data/local/tmp/gl/handover.sh
#!/system/bin/sh
pm enable com.amazon.tv.launcher
pm disable com.amazon.tv.launcher/.ui.HomeActivity_vNext
pm disable-user --user 0 com.amazon.tv.oobe || true
pm disable-user --user 0 com.amazon.firehomestarter || true
cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity
settings put secure bootanim.real_home_ready 1
settings put global private_dns_specifier dns.adguard-dns.com
settings put global private_dns_mode hostname
pm hide --user 0 com.amazon.device.software.ota || true
pm hide --user 0 com.amazon.device.software.ota.override || true
pm hide --user 0 com.amazon.tv.forcedotaupdater.v2 || true
EOF
chmod 755 /data/local/tmp/gl/handover.sh"
```

Trigger the root execution:
```bash
# On Fire OS 6 (mantis):
adb -s <TV_IP>:5555 shell "cd /data/local/tmp/gl && ./ghostlock_root --profile ./mantis-NS6711-5908.conf --tries 1 --exec ./handover.sh"

# On Fire OS 7 (kara / sheldon):
adb -s <TV_IP>:5555 shell "cd /data/local/tmp/gl && ./ghostlock_root --exec ./handover.sh"
```

### Step 4: Verification
Verify default Home resolver:
```bash
adb -s <TV_IP>:5555 shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"
# Should output: com.gathin.tvhome/.MainActivity
```

Press Home button:
```bash
adb -s <TV_IP>:5555 shell "input keyevent 3"
```
CleanYourTV appears immediately on your television screen.
