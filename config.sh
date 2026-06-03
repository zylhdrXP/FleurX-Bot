#!/bin/bash

# Kernel Configuration
KERNEL_PATH="${KERNEL_PATH:-$ROOT_DIR/kernel/xiaomi/sm7435}"

if [ -z "${BASE_BRANCH:-}" ]; then
    if git -C "$KERNEL_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        BASE_BRANCH="$(git -C "$KERNEL_PATH" rev-parse --abbrev-ref HEAD)"
        if [ "$BASE_BRANCH" = "HEAD" ] || [ -z "$BASE_BRANCH" ]; then
            BASE_BRANCH="lineage-23.2"
        fi
    else
        BASE_BRANCH="lineage-23.2"
    fi
fi

MAKEFILE_PATH="${MAKEFILE_PATH:-$KERNEL_PATH/Makefile}"
KERNEL_IMG="${KERNEL_IMG:-$ROOT_DIR/out/target/product/garnet/kernel}"

# Version Detection
if [ -f "$MAKEFILE_PATH" ]; then
    VERSION="${VERSION:-$(awk -F' = ' '/^SUBLEVEL =/ {print $2; exit}' "$MAKEFILE_PATH")}"
fi
VERSION="${VERSION:-256}"

# Release Configuration
RELEASE_REPO="${RELEASE_REPO:-zylhdrXP/FleurX-Release}"
ANYKERNEL_URL="${ANYKERNEL_URL:-https://github.com/zylhdrXP/AnyKernel3}"
ANYKERNEL_DIR="${ANYKERNEL_DIR:-$ROOT_DIR/AnyKernel3}"

# Variant Configuration
KSUN_SUSFS_SETUP_URL="${KSUN_SUSFS_SETUP_URL:-https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/dev-susfs/kernel/setup.sh}"
KSUN_SUSFS_SETUP_BRANCH="${KSUN_SUSFS_SETUP_BRANCH:-dev-susfs}"
SUSFS_REPO_URL="${SUSFS_REPO_URL:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_REPO_BRANCH="${SUSFS_REPO_BRANCH:-gki-android12-5.10}"
SUSFS_PATCH_NAME="${SUSFS_PATCH_NAME:-50_add_susfs_in_gki-android12-5.10.patch}"

DROIDSPACES_REMOTE_BRANCH="${DROIDSPACES_REMOTE_BRANCH:-droidspaces}"
DROIDSPACES_CHERRY_PICK_RANGE="${DROIDSPACES_CHERRY_PICK_RANGE:-fa49a18078eb34467f924a848f9e6a23ef4835d7^..31cc9c443048e0e830b08b47953739eea6460402}"
KSU_NEXT_SETUP_URL="${KSU_NEXT_SETUP_URL:-https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh}"
KSU_NEXT_SETUP_BRANCH="${KSU_NEXT_SETUP_BRANCH:-dev}"

# State Configuration
STATE_REPO_PATH="${STATE_REPO_PATH:-$SCRIPT_DIR}"
STATE_FILE="${STATE_FILE:-$STATE_REPO_PATH/.state/last_kernel_build_commit}"
STATE_REMOTE="${STATE_REMOTE:-origin}"
STATE_BRANCH="${STATE_BRANCH:-}"
STATE_AUTO_PUSH="${STATE_AUTO_PUSH:-1}"

# Changelog Configuration
CHANGELOG_MAX_LINES="${CHANGELOG_MAX_LINES:-20}"
CHANGELOG_MAX_CHARS="${CHANGELOG_MAX_CHARS:-900}"
CHANGELOG_FALLBACK_COMMITS="${CHANGELOG_FALLBACK_COMMITS:-30}"
CHANGELOG_GITHUB_URL="${CHANGELOG_GITHUB_URL:-https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435/commits/$BASE_BRANCH/}"
