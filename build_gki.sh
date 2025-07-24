#!/bin/bash
#
# build.sh
# Automated kernel build script with advanced Telegram notifications.
#

# --- CONFIGURATION ---
# Project and device details for notifications
PROJECT_NAME="Project Name Here"
DEVICE_CODENAME="Your Device Codename Here"

# Build versioning
REL="v1.0"
KERNEL_FLAVOR="GKI-5.10" 
ZIP_BASENAME="${KERNEL_FLAVOR}-${REL}"

# Telegram API credentials
BOT_TOKEN="telegram_bot_token_here"
CHAT_ID="chat_id_here"


WORK_DIR=$(pwd)
ANYKERNEL_DIR="${WORK_DIR}/anykernel"
ANYKERNEL_REPO="https://github.com/pavelc4-playground/AnyKernel3.git"
ANYKERNEL_BRANCH="marble"
IMAGE_PATH="$WORK_DIR/out/android12-5.10/dist/Image"
ZIP_NAME="${ZIP_BASENAME}.zip"

# Colors for console output
red='\033[0;31m'
green='\e[0;32m'
white='\033[0m'
yellow='\033[0;33m'



# Function to send a simple text message to Telegram
send_telegram_message() {
    local message_text="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message_text}" \
        -d "parse_mode=Markdown" > /dev/null
}

# Function to upload the final zip with a detailed success caption
upload_and_notify_success() {
    local file_path="$1"
    local duration_formatted="$2"

    echo -e "$yellow>> Calculating file details...$white"
    local zip_filename=$(basename "$file_path")
    local zip_size=$(du -h "$file_path" | awk '{print $1}')
    local zip_md5=$(md5sum "$file_path" | awk '{print $1}')
    local zip_sha256=$(sha256sum "$file_path" | awk '{print $1}')

    local success_caption
    success_caption="🎉 *BUILD COMPLETE: SUCCESS!* 🎉

Your kernel has been compiled successfully. Great job!

*Project:* **${PROJECT_NAME}**
*Device:* **\`${DEVICE_CODENAME}\`**
*Compilation Time:* **\`${duration_formatted}\`**

*File Name:* **\`${zip_filename}\`**
*File Size:* **\`${zip_size}\`**
*MD5 Checksum:* \`${zip_md5}\`
*SHA256 Checksum:* \`${zip_sha256}\`

---
*New kernel has arrived... Enjoy!*"

    echo -e "$yellow>> Uploading kernel zip to Telegram...$white"
    curl -s -F "chat_id=${CHAT_ID}" \
             -F "document=@${file_path}" \
             -F "caption=${success_caption}" \
             -F "parse_mode=Markdown" \
             "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" > /dev/null

    echo -e "$green>> Build finished successfully! Notification and zip sent.$white"
}

# --- BUILD FUNCTIONS ---

# This function is called by 'trap' when a command fails
failure_notification() {
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_formatted=$(printf '%dh:%dm:%ds\n' $(($duration/3600)) $(($duration%3600/60)) $(($duration%60)))
    
    # Grabs the last 20 lines from the build log. Assumes you run with '... > build.log 2>&1'
    local error_log=$(tail -n 20 build.log)

    local final_message
    final_message="☠️ *BUILD FAILED* ☠️

Unfortunately, the compilation process has failed.

*Project:* **${PROJECT_NAME}**
*Device:* **\`${DEVICE_CODENAME}\`**
*Elapsed Time:* **\`${duration_formatted}\`**

*Error Cause (Last Log):*
\`\`\`
$error_log
\`\`\`

Please check the full log for further investigation. Don't give up! 💪"
    
    send_telegram_message "$final_message"
    echo -e "$red>> Build failed! Error notification sent.$white"
    exit 1
}

# Function to package the kernel into a flashable zip
pack_kernel() {
    echo -e "\n$yellow << Packing kernel >> \n$white"
    
    # Clean previous AnyKernel checkout
    rm -rf "$ANYKERNEL_DIR"
    
    # Clone AnyKernel repository
    git clone --depth 1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_DIR"

    # Copy kernel image and zip the contents
    cp "$IMAGE_PATH" "$ANYKERNEL_DIR/Image"
    cd "$ANYKERNEL_DIR" || exit
    zip -r9 "$WORK_DIR/$ZIP_NAME" ./*
    
    # Return to working directory
    cd "$WORK_DIR"
}

# --- MAIN SCRIPT EXECUTION ---

# Clean previous build artifacts
echo -e "$red << Cleaning up old artifacts >> \n$white"
rm -rf out/
rm -f *.zip
rm -f build.log

# Record start time and send initial notification
start_time=$(date +%s)
build_date=$(TZ='Asia/Jakarta' date '+%d %B %Y, %H:%M:%S WIB')
system_uptime=$(uptime -p)

send_telegram_message "🚀 *New Build Initialized!*

A new compilation process has been started for a kernel.

*Project:* **${PROJECT_NAME}**
*Device:* **\`${DEVICE_CODENAME}\`**
*Host:* **\`aether prjkt\`**
*Uptime:* **\`$system_uptime\`**
*Started at:* **\`$build_date\`**"

# Set up automatic failure detection. Any command that fails will trigger 'failure_notification'
trap 'failure_notification' ERR
set -e

# Start the build process and log output to a file
echo -e "\n$yellow << Building kernel... This will take some time. >> \n$white"
LTO=thin BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh > build.log 2>&1

# If the script reaches this point, the build was successful.
# Disable the failure trap.
trap - ERR

# Package the successful build
pack_kernel

# Calculate total duration
end_time=$(date +%s)
duration=$((end_time - start_time))
duration_formatted=$(printf '%dh:%dm:%ds\n' $(($duration/3600)) $(($duration%3600/60)) $(($duration%60)))

# Upload the zip and send the final success notification
upload_and_notify_success "$ZIP_NAME" "$duration_formatted"
