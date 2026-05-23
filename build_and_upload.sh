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

escape_html() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

upload_pastebin() {
    local content="$1"
    local title="$2"

    if [ -z "${PASTEBIN_API_KEY:-}" ]; then
        return 1
    fi

    local response
    response=$(curl -fsS \
        --data-urlencode "api_paste_code=${content}" \
        --data-urlencode "api_paste_name=${title}" \
        --data-urlencode "api_paste_private=1" \
        --data-urlencode "api_paste_expire_date=1W" \
        --data-urlencode "api_option=paste" \
        --data-urlencode "api_dev_key=${PASTEBIN_API_KEY}" \
        "https://pastebin.com/api/api_post.php") || return 1

    if printf '%s' "$response" | grep -q "^https://pastebin.com/"; then
        local paste_id
        paste_id="$(printf '%s' "$response" | sed -n 's#^https://pastebin.com/##p')"
        if [ -n "$paste_id" ]; then
            printf 'https://pastebin.com/raw/%s' "$paste_id"
            return 0
        fi
    fi

    return 1
}

persist_last_build_commit() {
    local commit="$1"

    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$commit" > "$STATE_FILE"

    if [ "$STATE_AUTO_PUSH" != "1" ]; then
        return 0
    fi

    if ! git -C "$STATE_REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die "State repo path $STATE_REPO_PATH is not a git repository."
    fi

    local branch="$STATE_BRANCH"
    if [ -z "$branch" ]; then
        branch="$(git -C "$STATE_REPO_PATH" rev-parse --abbrev-ref HEAD)"
    fi
    if [ "$branch" = "HEAD" ]; then
        die "State repo is in detached HEAD. Set STATE_BRANCH to push."
    fi

    git -C "$STATE_REPO_PATH" add "$STATE_FILE_REL"
    if git -C "$STATE_REPO_PATH" diff --cached --quiet -- "$STATE_FILE_REL"; then
        return 0
    fi
    git -C "$STATE_REPO_PATH" commit -m "chore: update last kernel build commit" --only "$STATE_FILE_REL"
    git -C "$STATE_REPO_PATH" push "$STATE_REMOTE" "$branch"
}

telegram_send_document() {
    local file_path="$1"
    local caption="$2"
    local response http_code json_response

    response=$(curl -sS -w "\nHTTP_STATUS:%{http_code}" \
        -F "chat_id=${CHAT_ID}" \
        -F document=@"$file_path" \
        --form-string "caption=$caption" \
        -F parse_mode="HTML" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument") || return 1

    http_code=$(printf '%s' "$response" | awk -F: '/HTTP_STATUS/ {print $2}')
    json_response=$(printf '%s' "$response" | sed '/HTTP_STATUS/d')
    if [ "$http_code" == "200" ] && printf '%s' "$json_response" | grep -q '"ok":true'; then
        return 0
    fi

    echo "Error: Telegram upload failed with status $http_code"
    echo "Response: $json_response"
    return 1
}

telegram_send_message() {
    local message="$1"
    local response http_code json_response

    response=$(curl -sS -w "\nHTTP_STATUS:%{http_code}" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=HTML" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage") || return 1

    http_code=$(printf '%s' "$response" | awk -F: '/HTTP_STATUS/ {print $2}')
    json_response=$(printf '%s' "$response" | sed '/HTTP_STATUS/d')
    if [ "$http_code" == "200" ] && printf '%s' "$json_response" | grep -q '"ok":true'; then
        return 0
    fi

    echo "Error: Telegram message failed with status $http_code"
    echo "Response: $json_response"
    return 1
}

get_next_release_version() {
    local tags="" max_major=-1 max_minor=-1

    if command -v gh >/dev/null 2>&1; then
        tags="$(gh release list --repo "$RELEASE_REPO" --limit 200 --json tagName -q '.[].tagName' 2>/dev/null || true)"
    fi

    if [ -n "$tags" ]; then
        while IFS= read -r tag; do
        tag="${tag#v}"
        if [[ "$tag" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
            local major="${BASH_REMATCH[1]}"
            local minor="${BASH_REMATCH[2]}"
            if [ "$major" -gt "$max_major" ] || { [ "$major" -eq "$max_major" ] && [ "$minor" -gt "$max_minor" ]; }; then
                max_major="$major"
                max_minor="$minor"
            fi
        fi
    done <<< "$tags"

    if [ "$max_major" -lt 0 ]; then
        printf '1.0'
    else
        printf '%s.%s' "$max_major" "$((max_minor + 1))"
    fi
}

set_variant_from_choice() {
    local choice="$1"

    case $choice in
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
            die "Invalid variant choice: $choice"
            ;;
    esac
}

clean_kernel_source() {
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
        if [ "${FORCE_CLEAN:-}" = "1" ] || [ "${DIRTY_OK:-}" = "1" ]; then
            echo "Discarding local changes."
        else
            read -r -p "Discard local changes and continue? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Aborted."
                terminate 1
            fi
            DIRTY_OK=1
        fi
    fi

    git fetch --unshallow 2>/dev/null || true
    git fetch origin "$BASE_BRANCH"
    git reset --hard "origin/$BASE_BRANCH"
    rm -rf KernelSU* susfs4ksu

    cd - > /dev/null
}

apply_variant_choice() {
    local choice="$1"

    cd "$KERNEL_PATH" || terminate 1
    if [ "$choice" == "1" ]; then
        echo "Setting up KSUN with SUSFS..."
        curl -fsSL "https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/dev-susfs/kernel/setup.sh" | bash -s dev-susfs
        git clone --depth=1 -b gki-android12-5.10 https://gitlab.com/simonpunk/susfs4ksu.git
        cp susfs4ksu/kernel_patches/fs/* fs/
        cp susfs4ksu/kernel_patches/include/linux/* include/linux/
        cp susfs4ksu/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch .
        patch -p1 < 50_add_susfs_in_gki-android12-5.10.patch
    elif [ "$choice" == "2" ]; then
        echo "Applying Droidspaces cherry-picks and KSU-Next setup..."
        git fetch origin droidspaces
        git cherry-pick fa49a18078eb34467f924a848f9e6a23ef4835d7^..31cc9c443048e0e830b08b47953739eea6460402
        curl -fsSL "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s dev
    elif [ "$choice" == "3" ]; then
        echo "Vanilla variant selected. Staying on clean source."
    fi

    cd - > /dev/null
}

build_kernel() {
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
}

prepare_anykernel_dir() {
    if [ -d "$ANYKERNEL_DIR" ]; then
        rm -rf "$ANYKERNEL_DIR"
    fi
    git clone --depth=1 "https://github.com/zylhdrXP/AnyKernel3" "$ANYKERNEL_DIR"
}

package_zip() {
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
    cd - > /dev/null
}

generate_changelog() {
    LAST_BUILD_COMMIT=""
    if [ -f "$STATE_FILE" ]; then
        LAST_BUILD_COMMIT="$(head -n1 "$STATE_FILE" | tr -d '[:space:]')"
    fi

    HEAD_COMMIT="$(git -C "$KERNEL_PATH" rev-parse HEAD)"
    if [ -n "$LAST_BUILD_COMMIT" ] && ! git -C "$KERNEL_PATH" merge-base --is-ancestor "$LAST_BUILD_COMMIT" "$HEAD_COMMIT"; then
        echo "Last build commit not in history. Falling back to recent commits."
        LAST_BUILD_COMMIT=""
    fi

    CHANGELOG_LINES=""
    CHANGELOG_RANGE=""
    if [ -n "$LAST_BUILD_COMMIT" ] && [ "$LAST_BUILD_COMMIT" != "$HEAD_COMMIT" ]; then
        RANGE_START="$(git -C "$KERNEL_PATH" rev-list --reverse --max-count=1 "${LAST_BUILD_COMMIT}..${HEAD_COMMIT}")"
        CHANGELOG_RANGE="$(git -C "$KERNEL_PATH" rev-parse --short "$RANGE_START")..$(git -C "$KERNEL_PATH" rev-parse --short "$HEAD_COMMIT")"
        CHANGELOG_LINES="$(git -C "$KERNEL_PATH" log --reverse --pretty=format:'- %s (%h)' "${LAST_BUILD_COMMIT}..${HEAD_COMMIT}")"
    elif [ -n "$LAST_BUILD_COMMIT" ] && [ "$LAST_BUILD_COMMIT" = "$HEAD_COMMIT" ]; then
        CHANGELOG_RANGE="$(git -C "$KERNEL_PATH" rev-parse --short "$HEAD_COMMIT")"
        CHANGELOG_LINES="No new commits since last build."
    else
        RANGE_START="$(git -C "$KERNEL_PATH" rev-list --reverse --max-count=1 "$HEAD_COMMIT" | head -n1)"
        CHANGELOG_RANGE="$(git -C "$KERNEL_PATH" rev-parse --short "$RANGE_START")..$(git -C "$KERNEL_PATH" rev-parse --short "$HEAD_COMMIT")"
        CHANGELOG_LINES="$(git -C "$KERNEL_PATH" log --reverse --max-count="$CHANGELOG_FALLBACK_COMMITS" --pretty=format:'- %s (%h)' "$HEAD_COMMIT")"
    fi

    CHANGELOG_LINE_COUNT="$(printf '%s\n' "$CHANGELOG_LINES" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    CHANGELOG_TOO_LONG=0
    CHANGELOG_LINK=""
    if [ "$CHANGELOG_LINE_COUNT" -gt "$CHANGELOG_MAX_LINES" ] || [ "${#CHANGELOG_LINES}" -gt "$CHANGELOG_MAX_CHARS" ]; then
        CHANGELOG_TOO_LONG=1
        CHANGELOG_LINK="$(upload_pastebin "$CHANGELOG_LINES" "FleurX ${DATE}" || true)"
        if [ -z "$CHANGELOG_LINK" ]; then
            CHANGELOG_LINK="$CHANGELOG_GITHUB_URL"
        fi
    fi
}

build_variant() {
    local choice="$1"
    local ci_suffix="$2"

    set_variant_from_choice "$choice"
    clean_kernel_source
    HEAD_COMMIT="$(git -C "$KERNEL_PATH" rev-parse HEAD)"
    apply_variant_choice "$choice"
    build_kernel

    if [ -n "$ci_suffix" ]; then
        ZIP_NAME="FleurX-5.10.${VERSION}-${BUILD_TYPE}-${ci_suffix}-${DATE}.zip"
    else
        ZIP_NAME="FleurX-v${RELEASE_VERSION}-5.10.${VERSION}-${BUILD_TYPE}-${DATE}.zip"
    fi
    ZIP_PATH="$ROOT_DIR/$ZIP_NAME"

    package_zip
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

STATE_REPO_PATH="${STATE_REPO_PATH:-$SCRIPT_DIR}"
STATE_FILE="${STATE_FILE:-$STATE_REPO_PATH/.state/last_kernel_build_commit}"
STATE_REMOTE="${STATE_REMOTE:-origin}"
STATE_BRANCH="${STATE_BRANCH:-}"
STATE_AUTO_PUSH="${STATE_AUTO_PUSH:-1}"
STATE_FILE_REL="${STATE_FILE#$STATE_REPO_PATH/}"
if [ "$STATE_FILE_REL" = "$STATE_FILE" ]; then
    die "STATE_FILE must be inside STATE_REPO_PATH."
fi

CHANGELOG_MAX_LINES="${CHANGELOG_MAX_LINES:-20}"
CHANGELOG_MAX_CHARS="${CHANGELOG_MAX_CHARS:-900}"
CHANGELOG_FALLBACK_COMMITS="${CHANGELOG_FALLBACK_COMMITS:-30}"
RELEASE_REPO="${RELEASE_REPO:-zylhdrXP/FleurX-Release}"

# 1. Variant Selection
echo "Select Kernel Variant:"
echo "1) KSUN (Default)"
echo "2) KSUN-Droidspaces"
echo "3) Vanilla (Non-Root)"
echo "4) Build All Variants (Release)"
read -r -p "Enter choice [1-4]: " CHOICE

BUILD_ALL=0
case $CHOICE in
    1|2|3)
        set_variant_from_choice "$CHOICE"
        ;;
    4)
        BUILD_ALL=1
        ;;
    *)
        echo "Invalid choice. Defaulting to KSUN."
        CHOICE=1
        set_variant_from_choice "$CHOICE"
        ;;
esac

echo "------------------------------------------"
if [ "$BUILD_ALL" -eq 1 ]; then
    echo "Preparing all variants build..."
else
    echo "Preparing $VARIANT build..."
fi
echo "------------------------------------------"

# 2. Kernel Source Preparation (Unified Cleanup)
KERNEL_PATH="$ROOT_DIR/kernel/xiaomi/sm7435"
if git -C "$KERNEL_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE_BRANCH="$(git -C "$KERNEL_PATH" rev-parse --abbrev-ref HEAD)"
    if [ "$BASE_BRANCH" = "HEAD" ] || [ -z "$BASE_BRANCH" ]; then
        BASE_BRANCH="lineage-23.2"
    fi
else
    BASE_BRANCH="lineage-23.2"
fi

if [ ! -d "$KERNEL_PATH" ]; then
    die "Error: Kernel path $KERNEL_PATH not found!"
fi

if ! type -t m >/dev/null 2>&1; then
    die "m build command not found. Please source build/envsetup.sh before running."
fi

if type -t croot >/dev/null 2>&1; then
    croot
else
    cd "$ROOT_DIR"
fi

# 4. Packaging & Upload Setup
MAKEFILE_PATH="$ROOT_DIR/kernel/xiaomi/sm7435/Makefile"
CHANGELOG_GITHUB_URL="https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435/commits/lineage-23.2/"

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
if [ "$BUILD_ALL" -eq 1 ]; then
    RELEASE_VERSION="$(get_next_release_version)"
    clean_kernel_source
    generate_changelog
    prepare_anykernel_dir

    RELEASE_ASSETS=()
    RELEASE_VARIANTS=()
    for variant_choice in 1 2 3; do
        build_variant "$variant_choice" ""
        RELEASE_ASSETS+=("$ZIP_PATH")
        RELEASE_VARIANTS+=("$VARIANT")
    done

    read -r -p "Upload GitHub release? [y/N]: " RELEASE_CONFIRM
    if [[ "$RELEASE_CONFIRM" =~ ^[Yy]$ ]]; then
        require_cmd gh
        if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
            die "GH_TOKEN or GITHUB_TOKEN must be set to create GitHub releases."
        fi

        VARIANT_LIST="$(printf '%s, ' "${RELEASE_VARIANTS[@]}")"
        VARIANT_LIST="${VARIANT_LIST%, }"
        RELEASE_TAG="v${RELEASE_VERSION}"
        RELEASE_TITLE="FleurX v${RELEASE_VERSION} - 5.10.${VERSION} (${DATE})"

        if [ "$CHANGELOG_TOO_LONG" -eq 1 ]; then
            CHANGELOG_RELEASE_SECTION="Changelog: ${CHANGELOG_LINK}"
            CHANGELOG_TELEGRAM_SECTION="<a href=\"${CHANGELOG_LINK}\">Changelog</a>"
        else
            CHANGELOG_RELEASE_SECTION="Changelog:
${CHANGELOG_LINES}"
            CHANGELOG_TELEGRAM_SECTION="<pre>$(printf '%s' "$CHANGELOG_LINES" | escape_html)</pre>"
        fi

        RELEASE_NOTES="Date: ${DATE}
Release: v${RELEASE_VERSION}
Branch: ${BASE_BRANCH}
Variants: ${VARIANT_LIST}
Commits: ${CHANGELOG_RANGE}

${CHANGELOG_RELEASE_SECTION}"

        gh release create "$RELEASE_TAG" "${RELEASE_ASSETS[@]}" \
            --repo "$RELEASE_REPO" \
            --title "$RELEASE_TITLE" \
            --notes "$RELEASE_NOTES"

        RELEASE_URL="$(gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" --json url -q .url)"
        TELEGRAM_MESSAGE="<b>New FleurX Release</b>
🗓 <b>Date:</b> ${DATE}
🏷 <b>Release:</b> v${RELEASE_VERSION}
🔢 <b>Version:</b> 5.10.${VERSION}
🌳 <b>Branch:</b> ${BASE_BRANCH}
📦 <b>Variants:</b> ${VARIANT_LIST}
🔗 <b>Release:</b> <a href=\"${RELEASE_URL}\">GitHub Release</a>
🛠 <b>Changelog:</b> ${CHANGELOG_TELEGRAM_SECTION}"

        if ! telegram_send_message "$TELEGRAM_MESSAGE"; then
            die "Telegram release message failed."
        fi

        if [ -n "$HEAD_COMMIT" ]; then
            persist_last_build_commit "$HEAD_COMMIT"
        fi
    else
        echo "Skipping GitHub release."
    fi
else
    prepare_anykernel_dir
    build_variant "$CHOICE" "CI"
    generate_changelog

    if [ "$CHANGELOG_TOO_LONG" -eq 1 ]; then
        CHANGELOG_CI_BODY="<a href=\"${CHANGELOG_LINK}\">Changelog</a>"
    else
        CHANGELOG_CI_BODY="<pre>$(printf '%s' "$CHANGELOG_LINES" | escape_html)</pre>"
    fi

    read -r -p "Send build to Telegram? [y/N]: " SEND_TELEGRAM
    if [[ "$SEND_TELEGRAM" =~ ^[Yy]$ ]]; then
        CAPTION="<b>CI Kernel Build</b>

📱 <b>Variant:</b> ${VARIANT}
🗓 <b>Date:</b> ${DATE}
🔢 <b>Version:</b> 5.10.${VERSION}
🌳 <b>Branch:</b> ${BASE_BRANCH}
🔁 <b>Commits:</b> ${CHANGELOG_RANGE}
🛠 <b>Changelog:</b> ${CHANGELOG_CI_BODY}"
        if ! telegram_send_document "$ZIP_PATH" "$CAPTION"; then
            die "Telegram upload failed."
        fi
        if [ -n "$HEAD_COMMIT" ]; then
            persist_last_build_commit "$HEAD_COMMIT"
        fi
    fi
fi

# Prevent session from closing immediately (interactive shells only)
if [ -t 0 ]; then
    echo ""
    read -r -p "Process finished. Press Enter to exit..."
fi
