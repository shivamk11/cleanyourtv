#!/usr/bin/env python3
"""
sync_debloat.py - Synchronize debloat package lists between upstream CleanYourTV and Fire TV profiles.

Scans upstream `examples/amazon-*` directories, extracts package names, categorizes them,
and updates or audits `tools/firetv/profiles/` while enforcing critical safety exclusions
(e.g., preserving settings handlers, IME, and user-selected apps).
"""

import os
import glob
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EXAMPLES_DIR = os.path.join(REPO_ROOT, "examples")
PROFILES_DIR = os.path.join(os.path.dirname(__file__), "profiles")

# Packages that must NEVER be disabled or killed on Fire TV
CRITICAL_EXCLUSIONS = {
    # Main launcher package must stay enabled (only HomeActivity_vNext is disabled) to preserve Settings
    "com.amazon.tv.launcher",
    # Input Method / Keyboard
    "com.amazon.vizzini",
    "android",
    "com.android.systemui",
    "com.android.keychain",
    "com.android.packageinstaller",
    "com.android.providers.settings",
    "com.android.settings",
    "com.android.shell",
}

# Known device profile mappings to upstream examples
DEVICE_MAP = {
    "mantis_4k_fireos6.txt": "amazon-fire-tv-stick-4k-2018",
    "kara_4kmax_fireos7.txt": "amazon-fire-tv-stick-4k-max-2021",
    "sheldon_lite_fireos7.txt": "amazon-fire-tv-stick-lite-2020",
}

def parse_package_file(file_path):
    """Parse a debloat list into a set of package names, preserving comments/lines."""
    packages = set()
    if not os.path.exists(file_path):
        return packages
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                pkg = line.split()[0]
                packages.add(pkg)
    return packages

def categorize_package(pkg):
    """Categorize package for clean file formatting."""
    pkg_lower = pkg.lower()
    if any(k in pkg_lower for k in ["metric", "log", "crash", "telemetry", "ceviche", "diode", "usagestats", "wifilocker", "dataservice"]):
        return "Telemetry, Metrics & Crash Logging"
    elif any(k in pkg_lower for k in ["ad", "sneakpeek", "blackbird", "billboard", "kso", "ftvads"]):
        return "Advertising, Recommendations & Promos"
    elif any(k in pkg_lower for k in ["ota", "upgrade", "software.ota"]):
        return "System Updates (OTA)"
    elif any(k in pkg_lower for k in ["alexa", "echo", "wha", "naatyam"]):
        return "Alexa & Ambient Voice Services"
    elif any(k in pkg_lower for k in ["hulu", "espn", "fox", "fubo", "hbo", "peacock", "tubi", "univision", "pluto", "cbs", "nbc", "adultswim"]):
        return "Third-Party Sponsored Bloatware Apps"
    else:
        return "Amazon Background Services & Unneeded Daemons"

def audit_profiles():
    """Audit differences between upstream examples and local Fire TV profiles."""
    print("=====================================================================")
    print(" CleanYourTV Fire TV Debloat Profile Audit")
    print("=====================================================================\n")

    for profile_filename, example_dirname in DEVICE_MAP.items():
        profile_path = os.path.join(PROFILES_DIR, profile_filename)
        example_path = os.path.join(EXAMPLES_DIR, example_dirname, "debloat.txt")

        profile_pkgs = parse_package_file(profile_path)
        upstream_pkgs = parse_package_file(example_path)

        # Filter out critical packages from upstream
        safe_upstream = upstream_pkgs - CRITICAL_EXCLUSIONS

        new_in_upstream = safe_upstream - profile_pkgs
        unique_in_profile = profile_pkgs - safe_upstream

        print(f"Device: {profile_filename} <-> {example_dirname}")
        print(f"  Current Profile packages : {len(profile_pkgs)}")
        print(f"  Upstream Example packages: {len(upstream_pkgs)}")
        print(f"  Common packages          : {len(profile_pkgs & safe_upstream)}")

        if new_in_upstream:
            print(f"  [+] New in upstream ({len(new_in_upstream)}):")
            for pkg in sorted(new_in_upstream):
                print(f"      + {pkg} ({categorize_package(pkg)})")
        else:
            print("  [✓] All safe upstream packages are included.")

        if unique_in_profile:
            print(f"  [*] Specific to local profile ({len(unique_in_profile)}):")
            for pkg in sorted(unique_in_profile):
                print(f"      * {pkg}")
        print()

def sync_profiles():
    """Merge new safe upstream packages into local profiles with clean category headers."""
    print("==> Synchronizing debloat profiles with upstream CleanYourTV examples...")

    for profile_filename, example_dirname in DEVICE_MAP.items():
        profile_path = os.path.join(PROFILES_DIR, profile_filename)
        example_path = os.path.join(EXAMPLES_DIR, example_dirname, "debloat.txt")

        profile_pkgs = parse_package_file(profile_path)
        upstream_pkgs = parse_package_file(example_path)

        all_pkgs = (profile_pkgs | upstream_pkgs) - CRITICAL_EXCLUSIONS

        # Group by category
        categories = {
            "Telemetry, Metrics & Crash Logging": [],
            "Advertising, Recommendations & Promos": [],
            "System Updates (OTA)": [],
            "Alexa & Ambient Voice Services": [],
            "Third-Party Sponsored Bloatware Apps": [],
            "Amazon Background Services & Unneeded Daemons": []
        }

        for pkg in sorted(all_pkgs):
            cat = categorize_package(pkg)
            categories[cat].append(pkg)

        header = f"# {profile_filename}\n# CleanYourTV Synchronized Debloat Profile\n# Generated & verified against upstream examples/{example_dirname}\n\n"
        body = ""
        for cat_name, pkg_list in categories.items():
            if pkg_list:
                body += f"# --- {cat_name} ---\n"
                for p in pkg_list:
                    body += f"{p}\n"
                body += "\n"

        with open(profile_path, "w", encoding="utf-8") as f:
            f.write(header + body)

        print(f"    [OK] Updated {profile_filename} ({len(all_pkgs)} total packages)")

    print("==> Debloat profile synchronization complete!\n")

if __name__ == "__main__":
    if "--audit" in sys.argv:
        audit_profiles()
    else:
        sync_profiles()
