#!/usr/bin/env bash
# ==============================================================================
# CleanYourTV - Seamless Upstream Synchronization Tool
#
# Fetches upstream changes (launcher updates, debloat package lists, bug fixes),
# merges them into this repository, propagates launcher changes to isolated
# Fire TV targets (launcher-kara, launcher-mantis) with safety patches intact,
# syncs debloat profiles, and verifies the build.
#
# Usage:
#   tools/sync-upstream.sh [OPTIONS]
#
# Options:
#   --remote <name>   Upstream git remote name (default: origin)
#   --branch <name>   Upstream git branch name (default: main)
#   --audit           Only audit upstream changes (no modifications)
#   --no-build        Skip rebuilding APKs after synchronization
#   --push            Push synchronized branch to fork (myfork)
#   -h, --help        Show this help message
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE="origin"
BRANCH="main"
DO_BUILD=1
DO_PUSH=0
AUDIT_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --audit)
            AUDIT_ONLY=1
            shift
            ;;
        --no-build)
            DO_BUILD=0
            shift
            ;;
        --push)
            DO_PUSH=1
            shift
            ;;
        -h|--help)
            sed -n '2,19p' "$0" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

cd "$REPO_ROOT"

echo "====================================================================="
echo " CleanYourTV Upstream Synchronization"
echo " Upstream Remote : $REMOTE ($BRANCH)"
echo " Repository Root : $REPO_ROOT"
echo "====================================================================="

# 1. Fetch upstream
echo -e "\n[1/5] Fetching upstream updates from $REMOTE..."
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "Remote '$REMOTE' not found. Adding upstream: https://github.com/Gathin23/cleanyourtv.git"
    git remote add origin https://github.com/Gathin23/cleanyourtv.git
fi
git fetch "$REMOTE" "$BRANCH" --tags

LOCAL_HEAD=$(git rev-parse HEAD)
UPSTREAM_HEAD=$(git rev-parse "$REMOTE/$BRANCH")

if [ "$LOCAL_HEAD" = "$UPSTREAM_HEAD" ]; then
    echo "Already up-to-date with $REMOTE/$BRANCH ($LOCAL_HEAD)."
else
    COMMITS_BEHIND=$(git rev-list --count HEAD.."$REMOTE/$BRANCH")
    echo "Upstream is ahead by $COMMITS_BEHIND commit(s)."
fi

# Audit mode exits early
if [ "$AUDIT_ONLY" -eq 1 ]; then
    echo -e "\n[AUDIT] Running debloat profile audit..."
    python3 "$REPO_ROOT/tools/firetv/sync_debloat.py" --audit
    echo -e "\n[AUDIT] Complete."
    exit 0
fi

# 2. Merge upstream changes
echo -e "\n[2/5] Merging upstream $REMOTE/$BRANCH..."
# Because Fire TV files live in isolated directories (launcher-kara, launcher-mantis, tools/firetv),
# standard merges execute cleanly without conflicts.
if [ "$LOCAL_HEAD" != "$UPSTREAM_HEAD" ]; then
    git merge "$REMOTE/$BRANCH" --no-edit -m "merge: sync upstream cleanyourtv ($REMOTE/$BRANCH)" || {
        echo "Merge conflict encountered. Please resolve conflicts and re-run." >&2
        exit 1
    }
    echo "Merged upstream commits successfully."
fi

# 3. Propagate launcher changes to Fire TV targets
echo -e "\n[3/5] Propagating launcher updates to Fire TV variants..."
python3 "$REPO_ROOT/tools/firetv/sync_launchers.py"

# 4. Synchronize debloat profiles
echo -e "\n[4/5] Synchronizing debloat profiles with upstream examples..."
python3 "$REPO_ROOT/tools/firetv/sync_debloat.py"

# 5. Build verification
if [ "$DO_BUILD" -eq 1 ]; then
    echo -e "\n[5/5] Rebuilding all 4 launcher variants to verify integrity..."
    "$REPO_ROOT/tools/build-launcher.sh" all
    echo "All target APKs built and staged in dist/ successfully."
else
    echo -e "\n[5/5] Build step skipped (--no-build)."
fi

# Optional Push
if [ "$DO_PUSH" -eq 1 ]; then
    echo -e "\n==> Pushing changes to myfork..."
    git add launcher-kara launcher-mantis tools/firetv dist
    if ! git diff-index --quiet HEAD --; then
        git commit -m "chore: synchronize launcher variants and debloat profiles with upstream"
    fi
    git push myfork "$BRANCH"
    echo "Fork updated on GitHub."
fi

echo -e "\n====================================================================="
echo " Synchronization Complete! Upstream changes cleanly integrated."
echo "====================================================================="
