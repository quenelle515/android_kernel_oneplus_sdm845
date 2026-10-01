#!/bin/bash
set -e

# Configuration
DIR=$(readlink -f .)
MAIN=$(readlink -f ${DIR}/..)
KERNEL_DEFCONFIG=enchilada_defconfig
CLANG_DIR="$MAIN/toolchains/enchilada/clang"
KERNEL_DIR=$(pwd)
OUT_DIR="$KERNEL_DIR/out"
ZIMAGE_DIR="$OUT_DIR/arch/arm64/boot"
BUILD_START=$(date +"%s")

# Function to check for existing Clang
check_clang() {
    if [ -d "$CLANG_DIR" ] && [ -f "$CLANG_DIR/bin/clang" ]; then
        export PATH="$CLANG_DIR/bin:$PATH"
        export KBUILD_COMPILER_STRING="$($CLANG_DIR/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
        echo "Found existing Clang: $KBUILD_COMPILER_STRING"
        return 0
    fi
    return 1
}

# Install Clang if needed
if ! check_clang; then
    echo "No valid Clang found. Download and install Clang r536225?"
    echo "1. Yes"
    echo "2. No"
    read -p "Choose [1-2]: " clang_choice

    case "$clang_choice" in
        1)
            CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/7143812acf96c9af445b164656ae7f424a67a573/clang-r536225.tar.gz"
            ARCHIVE_NAME="clang.tar.gz"
            mkdir -p "$CLANG_DIR"
            wget -P "$MAIN" "$CLANG_URL" -O "$MAIN/$ARCHIVE_NAME" || exit 1
            tar -xf "$MAIN/$ARCHIVE_NAME" -C "$CLANG_DIR" || exit 1
            rm -f "$MAIN/$ARCHIVE_NAME"
            ;;
        2)
            echo "Exiting..."
            exit 1
            ;;


        *)
            echo "Invalid choice. Exiting..."
            exit 1
            ;;
    esac

    if ! check_clang; then
        echo "Clang installation failed. Exiting..."
        exit 1
    fi
fi

export KBUILD_BUILD_USER=root
export KBUILD_BUILD_HOST=f437836e782e
export KBUILD_BUILD_TIMESTAMP="Wed Sep 30 08:03:33 UTC 2026"
export KBUILD_BUILD_VERSION=1

# Set up toolchain
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

# Build kernel
make O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" $KERNEL_DEFCONFIG || exit 1
make -j23 O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" || exit 1

# Clean up old kernel zip files
echo "Cleaning up old kernel zip files..."
find "$KERNEL_DIR" -maxdepth 1 -type f -name "Enchilada-Kernel-*.zip" -exec rm -v {} \;

# Create temporary anykernel directory
TIME=$(date "+%Y%m%d-%H%M%S")
TEMP_ANY_KERNEL_DIR="$KERNEL_DIR/anykernel_temp"
rm -rf "$TEMP_ANY_KERNEL_DIR"

# Clone entire anykernel directory
echo "Cloning anykernel directory..."
if [ -d "$KERNEL_DIR/anykernel" ]; then
    cp -r "$KERNEL_DIR/anykernel" "$TEMP_ANY_KERNEL_DIR"
else
    echo "Error: anykernel directory not found!"
    exit 1
fi

# Copy kernel image
if [ -f "$ZIMAGE_DIR/Image.gz-dtb" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz-dtb" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image.gz" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image" ]; then
    cp -v "$ZIMAGE_DIR/Image" "$TEMP_ANY_KERNEL_DIR/"
fi

# Create zip file in kernel root directory
echo "Creating zip package..."
ZIP_NAME="Enchilada-Kernel-$TIME.zip"
cd "$TEMP_ANY_KERNEL_DIR"
zip -r9 "$KERNEL_DIR/$ZIP_NAME" ./*
cd ..

# Clean up temporary directory
rm -rf "$TEMP_ANY_KERNEL_DIR"

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo -e "\n=========================================="
echo "Build completed in $((DIFF / 60))m $((DIFF % 60))s"
echo "Final zip: $KERNEL_DIR/$ZIP_NAME"
echo "Zip size: $(du -h "$KERNEL_DIR/$ZIP_NAME" | cut -f1)"
echo "=========================================="
