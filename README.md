# Kernel Builder Script

A streamlined shell script to build, package, and distribute custom Android kernels. By default, it is configured for the Xiaomi SM7435 platform (Garnet), but it can be adapted for any device.

This utility automates the process of syncing the kernel source, applying specific patches or root solutions (such as KernelSU-Next and SUSFS), compiling the kernel, packaging it using AnyKernel3, and finally uploading the flashable zip to a designated Telegram chat.

## Features

* **Multiple Build Variants:** Easily switch between different kernel configurations.
  * **KSUN (Default):** Includes KernelSU-Next and SUSFS for advanced root management and hiding.
  * **KSUN-Droidspaces:** Includes KernelSU-Next with specific Droidspaces cherry-picks.
  * **Vanilla:** A standard, non-rooted kernel build.
* **Automated Source Management:** Automatically resets the tree, handles shallow/unshallow clones, and applies required patches.
* **AnyKernel3 Packaging:** Generates a ready-to-flash zip file upon successful compilation.
* **Telegram Integration:** Automatically formats a changelog and uploads the completed build to Telegram.

## Prerequisites

This script is designed to run within an initialized Android OS build environment (like LineageOS). 

Ensure you have the following installed and configured:
* A fully set up Android build environment (the script relies on `m` and `croot` commands provided by `build/envsetup.sh`).
* Standard system utilities: `bash`, `git`, `curl`, `zip`, `patch`.
* A Telegram Bot Token (created via BotFather).

## Setup

1. Clone the script from the root of your Android build tree.
2. Create a `.env` file in the root of Android build tree to store your Telegram credentials:

```env
BOT_TOKEN="your_telegram_bot_token"
CHAT_ID="your_telegram_chat_or_channel_id"
PASTEBIN_API_KEY="your_pastebin_api_key" # optional, used for long changelogs
```

## Usage

1. Initialize your build environment if you haven't already:
   ```bash
   source build/envsetup.sh
   lunch lineage_garnet-userdebug # or your specific lunch target
   ```

2. Execute the build script:
   ```bash
   ./FleurX-Bot/build_and_upload.sh
   ```

3. Follow the interactive prompt to select your desired kernel variant:
   ```text
   Select Kernel Variant:
   1) KSUN (Default)
   2) KSUN-Droidspaces
   3) Vanilla (Non-Root)
   ```

The script will handle the rest, from cleaning the source tree to uploading the final zip.

## Advanced Configuration

* **FORCE_CLEAN:** If you want to bypass the interactive prompt when uncommitted changes are detected in the kernel source, you can set `FORCE_CLEAN=1` before running the script.
  ```bash
  FORCE_CLEAN=1 ./FleurX-Bot//build_and_upload.sh
  ```

## Adapting for Other Devices

While the script is pre-configured for the Xiaomi SM7435 (Garnet), it can be easily modified for other devices, kernel sources, or AnyKernel3 configurations. Open `build_and_upload.sh` and update the following variables to match your environment:

* **Kernel Source & Branch:**
  * `KERNEL_PATH`: Change `"$ROOT_DIR/kernel/xiaomi/sm7435"` to your device's kernel path.
  * `Cherry-Picking Droidspaces`: https://github.com/zylhdrXP/FleurX-Bot/blob/202253f6d5dd35ccbf1e301f9093c09076c0dbab/build_and_upload.sh#L124 Check the last 4 commits first to avoid any conflict https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435/commits/droidspaces/
  * `BASE_BRANCH`: Change `"lineage-23.2"` to your kernel repository's default branch.
* **Build Paths & Naming:**
  * `KERNEL_IMG`: Update `"$ROOT_DIR/out/target/product/garnet/kernel"` to reflect your device codename.
  * `MAKEFILE_PATH`: Ensure this points to the `Makefile` inside your target `KERNEL_PATH`.
  * `ZIP_NAME`: Modify the base name (e.g., `FleurX`) to match your project.
* **AnyKernel3 Repository:**
  * Locate the AnyKernel3 clone command near the bottom of the script and replace `"https://github.com/zylhdrXP/AnyKernel3"` with your preferred AnyKernel3 repository link.
* **Telegram Integration:**
  * `CHANGELOG_GITHUB_URL`: Update the link to point to your repository's commit history.

* **Changelog Automation (Optional):**
  * The script tracks the last built commit in `FleurX-Bot/.state/last_kernel_build_commit` and commits/pushes it to keep history across ephemeral servers.
  * Requires git push access (token/SSH) for the FleurX-Bot repo.
  * `STATE_REPO_PATH` (default: script directory) controls where the state file is stored.
  * `STATE_REMOTE` (default: `origin`) and `STATE_BRANCH` (default: current branch) control where the state is pushed.
  * `STATE_AUTO_PUSH=0` disables auto-commit/push.
  * `CHANGELOG_MAX_LINES` (default 20) and `CHANGELOG_MAX_CHARS` (default 900) control when it uploads to Pastebin.
  * `CHANGELOG_FALLBACK_COMMITS` (default 30) is used when no prior build commit exists.

## Repository Information

* **Target Device:** Xiaomi SM7435 (Garnet)
* **Kernel Source:** [Fleur-Project](https://github.com/Fleur-Project/android_kernel_xiaomi_sm7435) (Branch: `lineage-23.2`)
* **Base Version:** 5.10.x
