# Upstream Synchronization & Architecture Guide

This repository maintains full compatibility with upstream [CleanYourTV](https://github.com/Gathin23/cleanyourtv) while providing first-class, standalone, plug-and-play support for Amazon Fire TV devices (Fire TV Stick 4K 1st Gen / Mantis, Fire TV Stick 4K Max 1st Gen / Kara, Sheldon Lite, etc.) alongside native Android TV and Google TV hardware.

---

## 1. Non-Conflicting Isolated Architecture

Upstream `cleanyourtv` frequently updates launcher UI features, widgets, bug fixes, translations, and debloat profiles in `examples/`. To prevent merge conflicts while maintaining specialized Fire OS optimizations, the repository is structured into isolated, independent components:

```
├── launcher/               # 100% upstream base Android TV launcher (minSdk 26)
├── launcher-kara/          # Standalone Fire OS 7 (API 28) target
├── launcher-mantis/        # Standalone Fire OS 6 (API 25) target with desugaring
├── examples/               # Upstream community debloat profiles for 480+ devices
├── tools/
│   ├── firetv/             # Self-contained Fire TV toolchain & specialized builds
│   │   ├── bin/            # Bundled GhostLock binaries & configs
│   │   ├── profiles/       # Curated Fire TV debloat lists (Mantis, Kara, Sheldon)
│   │   ├── setup.sh        # Fire TV zero-dependency installer
│   │   ├── install.sh      # Universal smart hardware/OS probe installer
│   │   ├── build-launcher.sh # Multi-target launcher builder (generic-tv, generic-box, kara, mantis)
│   │   ├── sync-upstream.sh  # Master upstream synchronization CLI
│   │   ├── sync_launchers.py # Automated launcher propagation script
│   │   └── sync_debloat.py   # Automated debloat list sync script
```

### Why this design eliminates merge conflicts
- Upstream changes to `launcher/`, `examples/`, `addons/`, or `docs/` merge cleanly via standard `git merge origin/main` because upstream never touches `launcher-kara/`, `launcher-mantis/`, or `tools/firetv/`.
- Generic Android TV and Google TV devices continue using standard upstream code (`launcher/`) via `cleanyourtv-generic-tv.apk` and `cleanyourtv-generic-box.apk`.
- Fire TV devices use their isolated, purpose-built targets (`cleanyourtv-kara.apk` and `cleanyourtv-mantis.apk`).

---

## 2. One-Command Upstream Synchronization

To pull all upstream changes (launcher updates, debloat lists, bug fixes), run:

```bash
./tools/firetv/sync-upstream.sh
```

### What happens automatically:
1. **Fetch & Merge**: Fetches `origin/main` (upstream `cleanyourtv`) and cleanly merges new commits.
2. **Launcher Code Propagation** (`tools/firetv/sync_launchers.py`):
   - Copies upstream `launcher/app/src/main/` into `launcher-kara/` and `launcher-mantis/`.
   - Injects the Fire TV 60s boot watchdog fix (`bootanim.real_home_ready = 1`).
   - Configures `show_inputs_pill = false` (Fire TV Sticks have 0 inputs).
   - Re-applies API 25 desugaring configuration for `mantis`.
3. **Debloat Profile Synchronization** (`tools/firetv/sync_debloat.py`):
   - Scans upstream `examples/amazon-*` debloat lists.
   - Merges newly discovered bloatware packages into `tools/firetv/profiles/`.
   - Categorizes them neatly into Telemetry, Ads, Sponsored Bloatware, and Services.
   - Enforces critical safety exclusions (e.g. keeping `com.amazon.tv.launcher` package enabled so the native 14-grid Settings hub is preserved).
4. **Build Verification** (`tools/firetv/build-launcher.sh all`):
   - Automatically compiles all 4 APK variants (`generic-tv`, `generic-box`, `kara`, `mantis`) to ensure zero build errors.
   - Stages release APKs into `dist/` and `tools/firetv/bin/`.

### CLI Options:
| Flag | Description |
|------|-------------|
| `--audit` | Report upstream debloat differences without modifying local files |
| `--no-build` | Skip compiling APKs after synchronization |
| `--push` | Commit and push synchronized changes to your GitHub fork (`myfork`) |
| `--remote <name>` | Upstream git remote name (default: `origin`) |
| `--branch <name>` | Upstream git branch name (default: `main`) |

---

## 3. Auditing Upstream Debloat Packages

To see what packages upstream contributors have added or updated without applying changes:

```bash
python3 tools/firetv/sync_debloat.py --audit
```

Sample audit output:
```text
=====================================================================
 CleanYourTV Fire TV Debloat Profile Audit
=====================================================================

Device: mantis_4k_fireos6.txt <-> amazon-fire-tv-stick-4k-2018
  Current Profile packages : 79
  Upstream Example packages: 68
  Common packages          : 68
  [✓] All safe upstream packages are included.
```

---

## 4. Automated GitHub Actions Sync

A GitHub Actions workflow is available at [`.github/workflows/upstream-sync.yml`](../.github/workflows/upstream-sync.yml):
- **Schedule**: Runs automatically every Monday at 04:00 UTC.
- **Manual Trigger**: Can be dispatched on-demand from the GitHub Actions tab (`Run workflow`).
- Automatically runs `sync-upstream.sh`, builds the APKs, and pushes updates.
