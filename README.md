# Kernel Builder Script

A streamlined shell script to build, package, and distribute custom Android kernels. By default, it is configured for the Xiaomi SM7435 platform (Garnet), but it can be adapted for any device.

This utility automates the process of syncing the kernel source, applying specific patches or root solutions (such as KernelSU-Next and SUSFS), compiling the kernel, packaging it using AnyKernel3, and finally uploading the flashable zip to a designated Telegram chat.

## Features

* **Multiple Build Variants:** Easily switch between different kernel configurations.
  * **KSUN (Default):** Includes KernelSU-Next and SUSFS for advanced root management and hiding.
  * **KSUN-Droidspaces:** Includes KernelSU-Next with specific Droidspaces cherry-picks.
  * **Vanilla:** A standard, non-rooted kernel build.
* **Automated Branch Detection:** Dynamically detects the current kernel branch (e.g., `lineage-23.2` or `linux-stable`) and includes it in release notes and Telegram captions.
* **Automated Versioning:** Automatically calculates the next release version based on existing GitHub tags and incorporates it into ZIP filenames for full releases (e.g., `FleurX-v1.1-...`).
* **Release Only Mode:** Option to upload existing ZIP files to Telegram or GitHub without rebuilding (Choice 5).
* **Automated Source Management:** Automatically resets the tree, handles shallow/unshallow clones, and applies required patches.
* **AnyKernel3 Packaging:** Generates a ready-to-flash zip file upon successful compilation.
* **Telegram Integration:** Automatically formats a changelog and uploads the completed build to Telegram with detailed metadata (Branch, Version, Variant, Commits).

## Prerequisites

This script is designed to run within an initialized Android OS build environment (like LineageOS). 

Ensure you have the following installed and configured:
* A fully set up Android build environment (the script relies on `m` and `croot` commands provided by `build/envsetup.sh`).
* Standard system utilities: `bash`, `git`, `curl`, `zip`, `patch`.
* A Telegram Bot Token (created via BotFather).
* `gh` (GitHub CLI) for automated versioning and publishing GitHub Releases (option 4 and 5).

## Setup

1. Clone the script from the root of your Android build tree.
2. Create a `.env` file in the root of Android build tree to store your credentials:

```env
BOT_TOKEN="your_telegram_bot_token"
CHAT_ID="your_telegram_chat_or_channel_id"
PASTEBIN_API_KEY="your_pastebin_api_key" # optional, used for long changelogs
GH_TOKEN="your_github_token" # or use GITHUB_TOKEN, required for releases and versioning
```

## Usage

1. Initialize your build environment:
   ```bash
   source build/envsetup.sh
   lunch lineage_garnet-userdebug
   ```

2. Execute the build script:
   ```bash
   ./FleurX-Bot/build_and_upload.sh
   ```

3. Follow the interactive prompt:
   ```text
   Select Kernel Variant:
   1) KSUN (Default)
   2) KSUN-Droidspaces
   3) Vanilla (Non-Root)
   4) Build All Variants (Release)
   5) Release Only (Upload Existing ZIPs)
   ```

**Mode Behaviors:**
* **Options 1-3:** Build a single variant, prompt for Telegram CI upload.
* **Option 4:** Builds all variants sequentially and creates a full GitHub Release + Telegram announcement.
* **Option 5:** Skips all build steps. Prompts to upload a single ZIP to Telegram or all variants to a new GitHub Release.

## Adapting for Other Devices

Update the following variables in `build_and_upload.sh` to match your environment:

* **Kernel Source & Branch:**
  * `KERNEL_PATH`: Change path to your device's kernel path.
  * `Cherry-Picking Droidspaces`: [Check commits here](https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435/commits/droidspaces/) and update the range in `apply_variant_choice` if needed.
  * `BASE_BRANCH`: Now automatically detected via `git rev-parse`. Fallback defaults to `lineage-23.2`.
* **Build Paths & Naming:**
  * `KERNEL_IMG`: Update to your device's kernel output path (e.g., `out/target/product/codename/kernel`).
  * `MAKEFILE_PATH`: Ensure this points to the `Makefile` inside your target `KERNEL_PATH`.
  * `ZIP_NAME`: Modify the base name (e.g., `FleurX`) in `build_variant`.
* **AnyKernel3 Repository:**
  * Update the URL in `prepare_anykernel_dir`.
* **Telegram Integration:**
  * `CHANGELOG_GITHUB_URL`: Update the link to point to your repository's commit history.

* **Changelog Automation (Optional):**
  * The script tracks the last built commit in `.state/last_kernel_build_commit` and can auto-push it.
  * `STATE_REPO_PATH` (default: script directory) controls where the state file is stored.
  * `STATE_REMOTE` (default: `origin`) and `STATE_BRANCH` control where the state is pushed.
  * `STATE_AUTO_PUSH=0` disables auto-commit/push.
  * `CHANGELOG_MAX_LINES` (default 20) and `CHANGELOG_MAX_CHARS` (default 900) control when it uploads to Pastebin.
  * `CHANGELOG_FALLBACK_COMMITS` (default 30) is used when no prior build commit exists.
* **GitHub Releases (Option 4 & 5):**
  * `RELEASE_REPO` (default: `zylhdrXP/FleurX-Release`) controls the release repository.
  * Release tag/title are auto-generated using the next available version (`v1.0`, `v1.1`, ...).

## Repository Information

* **Target Device:** Xiaomi SM7435 (Garnet)
* **Kernel Source:** [Fleur-Project](https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435)
* **Default Branch:** `lineage-23.2`
* **Base Version:** 5.10.x
