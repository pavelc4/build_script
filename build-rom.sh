#!/bin/bash
#
# build.sh
# Interactive Android build script with automated Telegram notifications and uploads.
#

# --- USER CONFIGURATION ---
# IMPORTANT: Fill in your own tokens and keys below before running the script.
# Do not upload these keys to a public repository.
export BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
export CHAT_ID="YOUR_CHAT_ID_HERE"
export PIXELDRAIN_API_KEY="YOUR_PIXELDRAIN_API_KEY_HERE"
# --- END OF CONFIGURATION ---


# Function to send a message to Telegram
send_telegram_message() {
    local message_text="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message_text}" \
        -d "parse_mode=Markdown" > /dev/null
}

# Function to upload a file to PixelDrain and return the link
upload_to_pixeldrain() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        echo "File to upload not found: $file_path"
        echo "Upload Failed"
        return
    fi
    
    echo "Uploading file to PixelDrain: $(basename "$file_path")"
    
    local response
    response=$(curl -s -X POST "https://pixeldrain.com/api/file" \
      -u ":$PIXELDRAIN_API_KEY" \
      -F "file=@$file_path")

    local file_id
    file_id=$(echo "$response" | grep -oP '"id"\s*:\s*"\K[^"]+')

    if [[ -n "$file_id" ]]; then
        echo "https://pixeldrain.com/u/$file_id"
    else
        echo "Upload Failed"
    fi
}

# Function to display how to use the script
usage() {
    echo "Usage: $0 \"<ROM Name>\" \"<Device Codename>\""
    echo "Example: $0 \"DerpFest 15.2\" \"marble\""
    exit 1
}

# Check for 'test' or 'help' arguments
if [[ "$1" == "test" ]]; then
    echo "Sending a test message to the Telegram bot..."
    send_telegram_message "✅ *Connection Test: SUCCESS!* 🤖

Hello there! This is your friendly build bot. If you're seeing this, we are perfectly connected.

Ready to compile some awesome ROMs! ⚡"
    echo "Test message has been sent."
    exit 0
elif [[ "$1" == "--help" || "$1" == "help" ]]; then
    usage
fi

# Check if the number of arguments is correct
if [ "$#" -ne 2 ]; then
    usage
fi

# --- BUILD VARIABLES FROM USER INPUT ---
ROM_NAME="$1"
DEVICE_CODENAME="$2"


# --- INTERACTIVE MENU FOR BUILD TYPE SELECTION ---
echo "------------------------------------------"
echo "Please select the build type:"
PS3=">> Enter your choice: "
options=("user (for public release)" "userdebug (for development & testing)" "eng (for engineering)" "beta (userdebug for testing)")
select opt in "${options[@]}"
do
    case $opt in
        "user (for public release)")
            BUILD_VARIANT="user"
            break
            ;;
        "userdebug (for development & testing)")
            BUILD_VARIANT="userdebug"
            break
            ;;
        "eng (for engineering)")
            BUILD_VARIANT="eng"
            break
            ;;
        "beta (userdebug for testing)")
            BUILD_VARIANT="userdebug"
            break
            ;;
        *) echo "Invalid option: $REPLY";;
    esac
done

BUILD_TARGET="lineage_${DEVICE_CODENAME}-bp1a-${BUILD_VARIANT}"
echo "------------------------------------------"
echo "Selected build target: $BUILD_TARGET"
echo "------------------------------------------"


# --- MAIN SCRIPT ---

start_time=$(date +%s)
build_date=$(TZ='Asia/Jakarta' date '+%d %B %Y, %H:%M:%S WIB')
echo "Build started at: $build_date"
system_uptime=$(uptime -p)

send_telegram_message "🚀 *New Build Initialized!*

A new compilation process has been started. Sit back, relax, and I'll notify you when it's done.

*ROM:* **$ROM_NAME**
*Device:* **\`$DEVICE_CODENAME\`**
*Target:* **\`$BUILD_TARGET\`**
*Host:* **\`aether prjkt\`**
*Uptime:* **\`$system_uptime\`**
*Started at:* **\`$build_date\`**"

set -e

# This function will be called if the build FAILS
trap 'failure_notification' ERR
failure_notification() {
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  duration_formatted=$(printf '%dh:%dm:%ds\n' $(($duration/3600)) $(($duration%3600/60)) $(($duration%60)))
  error_log=$(tail -n 20 nohup.out)
  
  final_message="☠️ *BUILD FAILED* ☠️

Unfortunately, the compilation process has failed.

*Device:* **\`$DEVICE_CODENAME\`**
*Elapsed Time:* **\`${duration_formatted}\`**

*Error Cause (Last Log):*
\`\`\`
$error_log
\`\`\`

Please check the full log (\`nohup.out\`) for further investigation. Don't give up! 💪"
  
  send_telegram_message "$final_message"
  echo "Build failed! Notification sent."
}

echo "Setting up build environment..."
source build/envsetup.sh

echo "Running lunch for target: $BUILD_TARGET"
lunch "$BUILD_TARGET"

echo "Updating API signatures to prevent build errors..."
m api-stubs-docs-non-updatable-update-current-api

echo "Cleaning previous build output (make clean)..."
make clean

echo "Starting compilation ('mka derp')... This will take a long time."
mka derp

# If the script reaches this point, the build was successful.
trap - ERR

end_time=$(date +%s)
duration=$((end_time - start_time))
duration_formatted=$(printf '%dh:%dm:%ds\n' $(($duration/3600)) $(($duration%3600/60)) $(($duration%60)))

zip_file_path=$(find "out/target/product/$DEVICE_CODENAME/" -name "*.zip" | tail -n 1)

if [ -z "$zip_file_path" ]; then
    zip_filename="Not found"
    zip_size="N/A"
    zip_md5="N/A"
    zip_sha256="N/A"
    download_link="Upload Failed: .zip file not found."
else
    zip_filename=$(basename "$zip_file_path")
    zip_size=$(du -h "$zip_file_path" | awk '{print $1}')
    zip_md5=$(md5sum "$zip_file_path" | awk '{print $1}')
    zip_sha256=$(sha256sum "$zip_file_path" | awk '{print $1}')
    download_link=$(upload_to_pixeldrain "$zip_file_path")
fi

final_message="🎉 *BUILD COMPLETE: SUCCESS!* 🎉

Your ROM has been compiled successfully. Great job!

*Device:* **\`$DEVICE_CODENAME\`**
*Compilation Time:* **\`${duration_formatted}\`**
*File Name:* **\`${zip_filename}\`**
*File Size:* **\`${zip_size}\`**
*MD5 Checksum:* \`${zip_md5}\`
*SHA256 Checksum:* \`${zip_sha256}\`

*Download Link:*
[$download_link]($download_link)

---
*New ROM has arrived... Enjoy!*"

send_telegram_message "$final_message"
echo "Build finished successfully! Notification and upload link sent."
