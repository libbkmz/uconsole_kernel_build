#!/bin/bash
set -x 

ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
JOBS=16
PI_BOOT_DIR=boot
MAIN_DIR=/mnt/axp20x_modules
KERNEL_DIR=/mnt/axp20x_modules/kernels/rpi-6.12.y-cm5/
TARGET_DIR=/mnt/axp20x_modules/target/cm5

# $PI_BOOT_DIR


make -j"$JOBS" -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" modules Image.gz dtbs

KERNEL_RELEASE=$(make -s -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)
ARCHIVE_NAME="rpi_kernel_modules_${PLATFORM}_${KERNEL_RELEASE}_$(date +%Y%m%d_%H%M%S).tar.gz"


make -j"$JOBS" -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" KDIR="$KERNEL_DIR" -f "$MAIN_DIR/Makefile.modules"

make -j"$JOBS" -C "$KERNEL_DIR" M="$MAIN_DIR/overlays" KDIR="$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE"


make -j"$JOBS" -C "$KERNEL_DIR"                        ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TARGET_DIR"     modules_install
make -j"$JOBS" -C "$KERNEL_DIR" M="$MAIN_DIR"          ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TARGET_DIR"     modules_install
make -j"$JOBS" -C "$KERNEL_DIR" M="$MAIN_DIR/overlays" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TARGET_DIR"     modules_install
# make -j"$JOBS" -C "$KERNEL_DIR"                        ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_HDR_PATH="$TARGET_DIR/usr" headers_install

make -j"$JOBS" -C "$KERNEL_DIR"                        ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_HDR_PATH="$TARGET_DIR/usr/lib/modules/$KERNEL_RELEASE/build" headers_install

mkdir -p "$TARGET_DIR/$PI_BOOT_DIR/"
mkdir -p "$TARGET_DIR/$PI_BOOT_DIR/overlays"

# CM5
cp "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" "$TARGET_DIR/$PI_BOOT_DIR/kernel_2712.img"
# CM4
# cp "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" "$TARGET_DIR/$PI_BOOT_DIR/kernel8.img"

cp "$KERNEL_DIR/arch/$ARCH/boot/dts/broadcom/"*.dtb "$TARGET_DIR/$PI_BOOT_DIR/"
cp "$KERNEL_DIR/arch/$ARCH/boot/dts/overlays/"*.dtb* "$TARGET_DIR/$PI_BOOT_DIR/overlays/"
cp "$KERNEL_DIR/arch/$ARCH/boot/dts/overlays/README" "$TARGET_DIR/$PI_BOOT_DIR/overlays/"

cp overlays/*.dtbo "$TARGET_DIR/$PI_BOOT_DIR/overlays/"


# echo "Creating archive of target directory..."
pushd "$TARGET_DIR" > /dev/null
tar czf "../$ARCHIVE_NAME" .
popd > /dev/null


echo "Installation commands:"
echo "cd /"
echo "tar xvf PATH/$ARCHIVE_NAME --strip-components=1 --keep-directory-symlink"
echo "rsync -avHK --no-delete $TARGET_DIR/ pi@raspberry_pi_ip:/"
