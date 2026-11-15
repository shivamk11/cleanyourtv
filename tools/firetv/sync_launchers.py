#!/usr/bin/env python3
"""
sync_launchers.py - Synchronize upstream launcher code to Fire TV targets.

Propagates changes from upstream `launcher/app/src/main/` to:
  - `launcher-kara/` (Fire OS 7 / API 28)
  - `launcher-mantis/` (Fire OS 6 / API 25 with desugaring)

Applies all Fire TV specific compatibility modifications cleanly and idempotently.
"""

import os
import shutil
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC_LAUNCHER = os.path.join(REPO_ROOT, "launcher")
KARA_LAUNCHER = os.path.join(REPO_ROOT, "launcher-kara")
MANTIS_LAUNCHER = os.path.join(REPO_ROOT, "launcher-mantis")

BOOTANIM_METHOD = """    private void dismissFireTvBootAnimation() {
        try {
            android.provider.Settings.Secure.putInt(getContentResolver(), "bootanim.real_home_ready", 1);
        } catch (Throwable ignored) {
        }
    }
"""

def sync_tree(src_dir, dst_dir):
    """Sync src_dir into dst_dir without deleting existing build files."""
    for root, dirs, files in os.walk(src_dir):
        # Exclude build caches or gradle dirs if any
        dirs[:] = [d for d in dirs if d not in {".gradle", "build"}]
        rel_path = os.path.relpath(root, src_dir)
        target_dir = os.path.join(dst_dir, rel_path)
        os.makedirs(target_dir, exist_ok=True)
        for f in files:
            src_file = os.path.join(root, f)
            dst_file = os.path.join(target_dir, f)
            shutil.copy2(src_file, dst_file)

def patch_config_xml(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()
    # Replace show_inputs_pill true with false
    new_content = re.sub(
        r'<bool name="show_inputs_pill">\s*true\s*</bool>',
        '<bool name="show_inputs_pill">false</bool>',
        content
    )
    with open(config_path, "w", encoding="utf-8") as f:
        f.write(new_content)

def patch_main_activity(activity_path, is_mantis=False):
    with open(activity_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Add dismissFireTvBootAnimation method if not present
    if "dismissFireTvBootAnimation()" not in content:
        # Insert before clockFormat or before onCreate
        insert_marker = "    private String clockFormat"
        if insert_marker in content:
            content = content.replace(insert_marker, BOOTANIM_METHOD + "\n" + insert_marker, 1)
        else:
            # Fallback before onCreate
            content = content.replace("protected void onCreate(", BOOTANIM_METHOD + "\n    @Override\n    protected void onCreate(", 1)

    # 2. Inject call in onCreate
    if "dismissFireTvBootAnimation();" not in content.split("onCreate(")[1].split("}")[0]:
        content = re.sub(
            r'(protected void onCreate\(Bundle [^\)]+\)\s*\{\s*super\.onCreate\([^\)]+\);)',
            r'\1\n        dismissFireTvBootAnimation();',
            content,
            count=1
        )

    # 3. Inject call in onResume
    if "onResume(" in content:
        resume_block = content.split("onResume()")[1].split("}")[0]
        if "dismissFireTvBootAnimation();" not in resume_block:
            content = re.sub(
                r'(protected void onResume\(\)\s*\{\s*super\.onResume\(\);)',
                r'\1\n        dismissFireTvBootAnimation();',
                content,
                count=1
            )

    # 4. If mantis (API 25), add guards for getChangedPackages
    if is_mantis:
        # Guard packagesChangedSinceRebuild
        if "if (Build.VERSION.SDK_INT < 26) return false;" not in content:
            content = re.sub(
                r'(private boolean packagesChangedSinceRebuild\(\)\s*\{)',
                r'\1\n        if (Build.VERSION.SDK_INT < 26) return false;',
                content,
                count=1
            )
        # Guard currentPackageSequence
        if "if (Build.VERSION.SDK_INT < 26) return since;" not in content:
            content = re.sub(
                r'(private int currentPackageSequence\(int since\)\s*\{)',
                r'\1\n        if (Build.VERSION.SDK_INT < 26) return since;',
                content,
                count=1
            )

    with open(activity_path, "w", encoding="utf-8") as f:
        f.write(content)

def patch_kara_gradle(gradle_path):
    with open(gradle_path, "r", encoding="utf-8") as f:
        content = f.read()

    # MinSdk 28
    content = re.sub(r'minSdk\s+\d+', 'minSdk 28', content)

    # Remove flavors if copied from launcher
    flavor_pattern = r'flavorDimensions\s+"formFactor"\s+productFlavors\s*\{[^}]*tv\s*\{[^}]*\}\s*box\s*\{[^}]*\}\s*\}'
    content = re.sub(flavor_pattern, '', content, flags=re.DOTALL)

    with open(gradle_path, "w", encoding="utf-8") as f:
        f.write(content)

def patch_mantis_gradle(gradle_path):
    with open(gradle_path, "r", encoding="utf-8") as f:
        content = f.read()

    # MinSdk 25
    content = re.sub(r'minSdk\s+\d+', 'minSdk 25', content)

    # Remove flavors if copied from launcher
    flavor_pattern = r'flavorDimensions\s+"formFactor"\s+productFlavors\s*\{[^}]*tv\s*\{[^}]*\}\s*box\s*\{[^}]*\}\s*\}'
    content = re.sub(flavor_pattern, '', content, flags=re.DOTALL)

    # Enable desugaring in compileOptions
    if "coreLibraryDesugaringEnabled true" not in content:
        content = re.sub(
            r'(compileOptions\s*\{)',
            r'\1\n        coreLibraryDesugaringEnabled true',
            content,
            count=1
        )

    # Add desugar dependency
    desugar_dep = '    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"'
    if desugar_dep not in content:
        content = re.sub(
            r'(dependencies\s*\{)',
            r'\1\n' + desugar_dep,
            content,
            count=1
        )

    with open(gradle_path, "w", encoding="utf-8") as f:
        f.write(content)

def main():
    print("==> Syncing upstream launcher source to launcher-kara...")
    sync_tree(
        os.path.join(SRC_LAUNCHER, "app", "src", "main"),
        os.path.join(KARA_LAUNCHER, "app", "src", "main")
    )
    patch_config_xml(os.path.join(KARA_LAUNCHER, "app", "src", "main", "res", "values", "config.xml"))
    patch_main_activity(os.path.join(KARA_LAUNCHER, "app", "src", "main", "java", "com", "gathin", "tvhome", "MainActivity.java"), is_mantis=False)
    patch_kara_gradle(os.path.join(KARA_LAUNCHER, "app", "build.gradle"))
    print("    [OK] launcher-kara updated.")

    print("==> Syncing upstream launcher source to launcher-mantis...")
    sync_tree(
        os.path.join(SRC_LAUNCHER, "app", "src", "main"),
        os.path.join(MANTIS_LAUNCHER, "app", "src", "main")
    )
    patch_config_xml(os.path.join(MANTIS_LAUNCHER, "app", "src", "main", "res", "values", "config.xml"))
    patch_main_activity(os.path.join(MANTIS_LAUNCHER, "app", "src", "main", "java", "com", "gathin", "tvhome", "MainActivity.java"), is_mantis=True)
    patch_mantis_gradle(os.path.join(MANTIS_LAUNCHER, "app", "build.gradle"))
    print("    [OK] launcher-mantis updated.")

    print("==> Upstream launcher synchronization complete!")

if __name__ == "__main__":
    main()
