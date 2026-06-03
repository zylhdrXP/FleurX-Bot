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

3. (Optional) Customize the build by editing `config.sh`. This file contains all the paths, branches, and repository URLs used by the script.

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

## Configuration Reference (`config.sh`)

The `config.sh` file centralizes all variables. Below is a complete reference of the available configuration options:

### Kernel Configuration
* `KERNEL_PATH`: Path to the kernel source directory.
* `BASE_BRANCH`: The base branch to sync and build from (e.g., `lineage-23.2`). Auto-detected if not set.
* `MAKEFILE_PATH`: Path to the kernel `Makefile` for version extraction.
* `KERNEL_IMG`: Path to the compiled kernel binary (e.g., `Image` or `Image.gz-dtb`).
* `VERSION`: Manual override for the kernel sublevel version (e.g., `256` for `5.10.256`). Auto-detected from `Makefile` if not set.

### Variant-Specific Setup
* **KSUN + SUSFS (Choice 1):**
  * `KSUN_SUSFS_SETUP_URL`: URL for the KernelSU-Next + SUSFS setup script.
  * `KSUN_SUSFS_SETUP_BRANCH`: Branch/argument for the setup script.
  * `SUSFS_REPO_URL`: Repository URL for SUSFS patches.
  * `SUSFS_REPO_BRANCH`: Branch for the SUSFS repository.
  * `SUSFS_PATCH_NAME`: Filename of the specific SUSFS patch to apply.
* **KSUN-Droidspaces (Choice 2):**
  * `DROIDSPACES_REMOTE_BRANCH`: Remote branch containing Droidspaces commits.
  * `DROIDSPACES_CHERRY_PICK_RANGE`: Git revision range for Droidspaces cherry-picks.
  * `KSU_NEXT_SETUP_URL`: URL for the standard KernelSU-Next setup script.
  * `KSU_NEXT_SETUP_BRANCH`: Branch/argument for the KSU-Next setup script.

### AnyKernel3 & Packaging
* `ANYKERNEL_URL`: Git URL for the AnyKernel3 repository used for zipping.
* `ANYKERNEL_DIR`: Local directory where AnyKernel3 will be cloned.

### GitHub & Telegram Integration
* `RELEASE_REPO`: The `owner/repo` path for creating GitHub Releases.
* `CHANGELOG_GITHUB_URL`: Base URL for the GitHub commit history (used in release notes).
* `PASTEBIN_API_KEY`: Required if you want to upload long changelogs to Pastebin.

### State & Changelog Management
* `STATE_REPO_PATH`: Path to the git repository tracking the build state.
* `STATE_FILE`: Absolute path to the file storing the last successful build's commit hash.
* `STATE_REMOTE`: Git remote to push state updates to.
* `STATE_BRANCH`: Git branch to push state updates to (auto-detected if empty).
* `STATE_AUTO_PUSH`: Set to `1` to enable automatic commit and push of the state file.
* `CHANGELOG_MAX_LINES`: Maximum number of lines in a changelog before it's moved to a paste service.
* `CHANGELOG_MAX_CHARS`: Maximum character count for Telegram messages.
* `CHANGELOG_FALLBACK_COMMITS`: Number of commits to show if no previous build state is found.



## Repository Information

* **Target Device:** Xiaomi SM7435 (Garnet)
* **Kernel Source:** [Fleur-Project](https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435)
* **Default Branch:** `lineage-23.2`
* **Base Version:** 5.10.x
