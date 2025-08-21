#!/bin/bash
#
# Kernel build automation script for GKI kernel
# Copyright (C) 2025 pavelc4
#

SECONDS=0
LOG_FILE="log.txt"
> "$LOG_FILE"

TC_DIR="$HOME/prebuilts/clang/host/linux-x86/llvm-21"
export PATH="$TC_DIR/bin:$PATH"

TG_TOKEN="YOUR_BOT_TOKEN"       
TG_CHAT_ID="YOUR_CHAT_ID"     

PROJECT_ID="Aether | Prjkt"
PROJECT_HOST="Aether | Prjkt"
LOCALVERSION_NAME="Chandelier"

ANYKERNEL_REPO="https://github.com/pavelc4-playground/AnyKernel3.git"
ANYKERNEL_DIR="AnyKernel3"

DO_CLEAN=false
NO_LTO=false
ONLY_CONFIG=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--clean)
            DO_CLEAN=true
            shift
            ;;
        -n|--no-lto)
            NO_LTO=true
            shift
            ;;
        -o|--only-config)
            ONLY_CONFIG=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

TARGET="$1"
KERNEL_VERSION="$2"

if [ -z "$TARGET" ] || [ -z "$KERNEL_VERSION" ]; then
    echo "Usage: $0 [--clean] <device> <version>"
    echo "Example: $0 marble 1.0"
    exit 1
fi

ZIP_NAME="${LOCALVERSION_NAME}-v${KERNEL_VERSION}.zip"
DEVICE_NAME="$TARGET GKI"

function format_time() {
    local DURATION=$1
    printf "%dh:%dm:%ds" $((DURATION / 3600)) $((DURATION % 3600 / 60)) $((DURATION % 60))
}

function m() {
    make -j$(nproc --all) O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 \
        TARGET_PRODUCT=$TARGET "$@" 2>&1 | tee -a "$LOG_FILE" || exit $?
}

function send_tg() {
    [ -z "$TG_TOKEN" ] && return
    [ -z "$TG_CHAT_ID" ] && return
    TEXT=$(printf "%s" "$1")
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" -d parse_mode="Markdown" -d text="$TEXT" > /dev/null
}

function tg_upload() {
    [ -z "$TG_TOKEN" ] && return
    [ -z "$TG_CHAT_ID" ] && return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
        -F chat_id="$TG_CHAT_ID" -F document=@"$1" > /dev/null
}

function pack_anykernel() {
    echo "Packing AnyKernel3..."
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        git clone --depth 1 "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"
    fi
    cp out/arch/arm64/boot/Image "$ANYKERNEL_DIR/"
    pushd "$ANYKERNEL_DIR" > /dev/null
    zip -r9 "../$ZIP_NAME" . -x .git README.md *placeholder
    popd > /dev/null
    echo "Packed: $ZIP_NAME"
}

UPTIME=$(uptime -p)
START_TIME_FMT=$(date +"%d %B %Y, %T %Z")

send_tg "🚀 *New Build Initialized!*

A new kernel compilation process has been started.

*Project:* \`$PROJECT_ID\`
*Device:* \`$DEVICE_NAME\`
*Host:* \`$PROJECT_HOST\`
*Uptime:* \`$UPTIME\`
*Started at:* \`$START_TIME_FMT\`"

$DO_CLEAN && { rm -rf out/; echo "Cleaned output directory."; }

mkdir -p out
echo "Generating config..."
m gki_defconfig
scripts/config --file out/.config --set-str LOCALVERSION "-${LOCALVERSION_NAME}"
scripts/config --file out/.config -d LTO_NONE -d LTO_CLANG_THIN -e LTO_CLANG_FULL
echo "Full LTO enabled by default."

$NO_LTO && { scripts/config --file out/.config -d LTO_CLANG_FULL -e LTO_NONE; echo "Disabled LTO!"; }
$ONLY_CONFIG && exit

echo "Building kernel Image..."
m Image

if [ -f "out/arch/arm64/boot/Image" ]; then
    echo "Image built successfully."
    pack_anykernel
    if [ -f "$ZIP_NAME" ]; then
        FILE_SIZE=$(du -h "$ZIP_NAME" | cut -f1)
        MD5_HASH=$(md5sum "$ZIP_NAME" | cut -d ' ' -f1)
        SHA256_HASH=$(sha256sum "$ZIP_NAME" | cut -d ' ' -f1)
        COMPILATION_TIME=$(format_time $SECONDS)

        send_tg "🎉 *BUILD COMPLETE: SUCCESS!* 🎉

Your kernel has been compiled successfully.

*Project:* \`$PROJECT_ID\`
*Device:* \`$DEVICE_NAME\`
*Compilation Time:* \`$COMPILATION_TIME\`

*File Name:* \`$ZIP_NAME\`
*File Size:* \`$FILE_SIZE\`
*MD5 Checksum:* \`$MD5_HASH\`
*SHA256 Checksum:* \`$SHA256_HASH\`

---
New kernel has arrived!"
        tg_upload "$ZIP_NAME"
    else
        send_tg "⚠️ Build succeeded for \`${DEVICE_NAME}\`, but the zip file was not found!"
        tg_upload "$LOG_FILE"
    fi
else
    COMPILATION_TIME=$(format_time $SECONDS)
    send_tg "❌ *BUILD FAILED!*

The kernel compilation process failed. Please check the attached log.

*Project:* \`$PROJECT_ID\`
*Device:* \`$DEVICE_NAME\`
*Host:* \`$PROJECT_HOST\`
*Compilation Time:* \`$COMPILATION_TIME\`"
    tg_upload "$LOG_FILE"
    exit 1
fi

echo "Completed in $(format_time $SECONDS)"
