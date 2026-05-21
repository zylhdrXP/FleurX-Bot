#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

terminate() {
    local code=${1:-0}
    exit "$code"
}

die() {
    echo "$1"
    terminate 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ROOT_DIR="${ROOT_DIR:-$PWD}"
cd "$ROOT_DIR"

# Load environment variables
ENV_FILE="$ROOT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
else
    die ".env file not found. Please create one with BOT_TOKEN and CHAT_ID."
fi

if [ -z "${BOT_TOKEN:-}" ] || [ -z "${CHAT_ID:-}" ]; then
    die "BOT_TOKEN and CHAT_ID must be set in .env."
fi

require_cmd git
require_cmd curl
require_cmd zip
require_cmd patch

# 1. Variant Selection
echo "Select Kernel Variant:"
echo "1) KSUN (Default)"
echo "2) KSUN-Droidspaces"
echo "3) Vanilla (Non-Root)"
read -r -p "Enter choice [1-3]: " CHOICE

case $CHOICE in
    1)
        VARIANT="KSUN"
        BUILD_TYPE="KSUN"
        ;;
    2)
        VARIANT="KSUN-Droidspaces"
        BUILD_TYPE="KSUN-DS"
        ;;
    3)
        VARIANT="Vanilla"
        BUILD_TYPE="Vanilla"
        ;;
    *)
        echo "Invalid choice. Defaulting to KSUN."
        VARIANT="KSUN"
        BUILD_TYPE="KSUN"
        CHOICE=1
        ;;
esac

echo "------------------------------------------"
echo "Preparing $VARIANT build..."
echo "------------------------------------------"

# 2. Kernel Source Preparation (Unified Cleanup)
KERNEL_PATH="$ROOT_DIR/kernel/xiaomi/sm7435"
BASE_BRANCH="lineage-23.2"

if [ ! -d "$KERNEL_PATH" ]; then
    die "Error: Kernel path $KERNEL_PATH not found!"
fi

echo "Cleaning up kernel source..."
cd "$KERNEL_PATH" || terminate 1

if ! git -C "$KERNEL_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Error: $KERNEL_PATH is not a git repository."
fi

if [ -f .git/CHERRY_PICK_HEAD ]; then
    die "Cherry-pick in progress. Resolve or abort before running this script."
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Uncommitted changes detected in $KERNEL_PATH."
    if [ "${FORCE_CLEAN:-}" = "1" ]; then
        echo "FORCE_CLEAN=1 set. Discarding local changes."
    else
        read -r -p "Discard local changes and continue? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            terminate 1
        fi
    fi
fi

git fetch --unshallow 2>/dev/null || true
git fetch origin "$BASE_BRANCH"
git reset --hard "origin/$BASE_BRANCH"
rm -rf KernelSU* susfs4ksu

# 3. Apply Variant Specific Logic
if [ "$CHOICE" == "1" ]; then
    echo "Setting up KSUN with SUSFS..."
    curl -fsSL "https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/dev-susfs/kernel/setup.sh" | bash -s dev-susfs
    git clone --depth=1 -b gki-android12-5.10 https://gitlab.com/simonpunk/susfs4ksu.git
    cp susfs4ksu/kernel_patches/fs/* fs/
    cp susfs4ksu/kernel_patches/include/linux/* include/linux/
    cp susfs4ksu/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch .
    patch -p1 < 50_add_susfs_in_gki-android12-5.10.patch

elif [ "$CHOICE" == "2" ]; then
    echo "Applying Droidspaces cherry-picks and KSU-Next setup..."
    git fetch origin droidspaces
    git cherry-pick fa49a18078eb34467f924a848f9e6a23ef4835d7^..31cc9c443048e0e830b08b47953739eea6460402
    curl -fsSL "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s dev

elif [ "$CHOICE" == "3" ]; then
    echo "Vanilla variant selected. Staying on clean source."
fi

# Return to root and execute build
cd - > /dev/null

if ! type -t m >/dev/null 2>&1; then
    die "m build command not found. Please source build/envsetup.sh before running."
fi

if type -t croot >/dev/null 2>&1; then
    croot
else
    cd "$ROOT_DIR"
fi

echo "Running m installclean and m bootimage..."
THREADS="$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN)"
if ! m installclean; then
    echo "Build clean failed! Aborting."
    terminate 1
fi
if ! m bootimage -j"$THREADS"; then
    echo "Build failed! Aborting."
    terminate 1
fi

# 4. Packaging & Upload Setup
MAKEFILE_PATH="$ROOT_DIR/kernel/xiaomi/sm7435/Makefile"
CHANGELOG_URL="https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435/commits/lineage-23.2/"

if [ -f "$MAKEFILE_PATH" ]; then
    VERSION="$(awk -F' = ' '/^SUBLEVEL =/ {print $2; exit}' "$MAKEFILE_PATH")"
else
    VERSION="256"
fi
if [ -z "$VERSION" ]; then
    VERSION="256"
fi

DATE=$(date +"%d%m%y")
KERNEL_IMG="$ROOT_DIR/out/target/product/garnet/kernel"
ANYKERNEL_DIR="$ROOT_DIR/AnyKernel3"
ZIP_NAME="FleurX-5.10.${VERSION}-${BUILD_TYPE}-${DATE}.zip"
ZIP_PATH="$ROOT_DIR/$ZIP_NAME"

# Create formatted caption for Telegram
CAPTION="<b>New Kernel Build is Up!</b>

📱 <b>Variant:</b> ${VARIANT}
🗓 <b>Date:</b> ${DATE}
🔢 <b>Version:</b> 5.10.${VERSION}
🛠 <b>Changelog:</b> <a href=\"${CHANGELOG_URL}\">GitHub Commits</a>"

# Clone AnyKernel3
if [ -d "$ANYKERNEL_DIR" ]; then
    rm -rf "$ANYKERNEL_DIR"
fi
git clone --depth=1 "https://github.com/zylhdrXP/AnyKernel3" "$ANYKERNEL_DIR"

# Move Kernel & Zip
if [ ! -f "$KERNEL_IMG" ]; then
    echo "Kernel image not found at $KERNEL_IMG. Aborting."
    terminate 1
fi

echo "Copying kernel and zipping..."
rm -f "$ANYKERNEL_DIR/Image"
cp "$KERNEL_IMG" "$ANYKERNEL_DIR/Image"
cd "$ANYKERNEL_DIR" || terminate 1
rm -f "$ZIP_PATH"
zip -r "$ZIP_PATH" . -x "*.git*"
cd ..

# 5. Upload to Telegram
echo "Uploading $VARIANT build to Telegram..."
UPLOAD_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendDocument"
if ! RESPONSE=$(curl -sS -w "\nHTTP_STATUS:%{http_code}" \
    -F "chat_id=${CHAT_ID}" \
    -F document=@"$ZIP_PATH" \
    --form-string "caption=$CAPTION" \
    -F parse_mode="HTML" \
    "$UPLOAD_URL"); then
    echo "------------------------------------------"
    echo "Error: Upload request failed."
    echo "------------------------------------------"
    terminate 1
fi

HTTP_CODE=$(printf '%s' "$RESPONSE" | awk -F: '/HTTP_STATUS/ {print $2}')
JSON_RESPONSE=$(printf '%s' "$RESPONSE" | sed '/HTTP_STATUS/d')
if [ -z "$HTTP_CODE" ]; then
    echo "------------------------------------------"
    echo "Error: Unable to parse HTTP status from response."
    echo "Response: $RESPONSE"
    echo "------------------------------------------"
    terminate 1
fi

if [ "$HTTP_CODE" == "200" ] && echo "$JSON_RESPONSE" | grep -q '"ok":true'; then
    echo "------------------------------------------"
    echo "Process completed successfully for $VARIANT."
    echo "------------------------------------------"
else
    echo "------------------------------------------"
    echo "Error: Upload failed with status $HTTP_CODE"
    echo "Response: $JSON_RESPONSE"
    echo "------------------------------------------"
    terminate 1
fi

# Prevent session from closing immediately (interactive shells only)
if [ -t 0 ]; then
    echo ""
    read -r -p "Process finished. Press Enter to exit..."
fi
