#!/bin/bash
set -e

# this script is made for cross compilation
# I didn't test it on real RPi hardware without cross-compiler
# idk how it will work in that case...

# Variables
KERNEL_DIR="/mnt/git_repos/rpi_linux"
ARCH="arm64"
CROSS_COMPILE="aarch64-linux-gnu-"
CONFIG_FILE="${KERNEL_DIR}/arch/${ARCH}/configs/bcm2712_defconfig"
JOBS=16
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
TARGET_DIR="$(readlink -f "${SCRIPT_DIR}/../target")"
ARCHIVE_NAME="rpi_kernel_modules_$(date +%Y%m%d_%H%M%S).tar.gz"
ENABLE_LOCALMODCONFIG=1
ENABLE_FULL_BUILD=1
REGEN_ONLY=0
CUSTOM_SUFFIX="bkmz1"

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --regen-config) REGEN_ONLY=1 ;;
        --enable-localmodconfig) ENABLE_LOCALMODCONFIG=1 ;;
        --disable-localmodconfig) ENABLE_LOCALMODCONFIG=0 ;;
        --enable-fullbuild) ENABLE_FULL_BUILD=1 ;;
        --disable-fullbuild) ENABLE_FULL_BUILD=0 ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --regen-config              Regenerate .config and exit"
            echo "  --enable-localmodconfig     Use localmodconfig (default)"
            echo "  --disable-localmodconfig    Skip localmodconfig"
            echo "  --enable-fullbuild          Enable full kernel build (default)"
            echo "  --disable-fullbuild         Skip full kernel build"
            exit 0
            ;;
        *)
            echo "Unknown parameter passed: $1"
            exit 1
            ;;
    esac
    shift
done

CONFIG_OPTIONS=(
    "CONFIG_REGMAP_I2C=y"
    "CONFIG_INPUT_AXP20X_PEK=y"
    "CONFIG_CHARGER_AXP20X=m"
    "CONFIG_BATTERY_AXP20X=m"
    "CONFIG_AXP20X_POWER=m"
    "CONFIG_MFD_AXP20X=y"
    "CONFIG_MFD_AXP20X_I2C=y"
    "CONFIG_REGULATOR_AXP20X=y"
#    "CONFIG_DRM_PANEL_CWD686=m"
#    "CONFIG_DRM_PANEL_CWU50=m"
#    "CONFIG_BACKLIGHT_OCP8178=m"
    "CONFIG_AXP20X_ADC=m"
    "CONFIG_TI_ADC081C=m"
    "CONFIG_CRYPTO_LIB_ARC4=y"
    "CONFIG_CRC_CCITT=y"

    # for more diagnostic things in case of trouble
    "CONFIG_MAGIC_SYSRQ_DEFAULT_ENABLE=0x1"

    "CONFIG_LOCALVERSION_AUTO=y"

    "CONFIG_DRM_CLIENT_LOG=y"
    "CONFIG_PANIC_TIMEOUT=10"
    "CONFIG_LOCKUP_DETECTOR=y"
    "CONFIG_SOFTLOCKUP_DETECTOR=y"
    "CONFIG_HARDLOCKUP_DETECTOR=y"
    "CONFIG_HARDLOCKUP_DETECTOR_BUDDY=y"
    "CONFIG_HARDLOCKUP_DETECTOR_COUNTS_HRTIMER=y"
    "CONFIG_WQ_WATCHDOG=y"
)

if [ ! -d "$KERNEL_DIR" ]; then
    echo "Error: Kernel directory not found at $KERNEL_DIR"
    exit 1
fi

# Define config manipulation function
apply_config_options() {
    local config_path="$1"
    local config_tool="${KERNEL_DIR}/scripts/config"

    if [ ! -f "$config_tool" ]; then
        echo "Error: Kernel config tool not found at $config_tool"
        exit 1
    fi
    if [ ! -f "$config_path" ]; then
        echo "Error: .config file not found at $config_path"
        exit 1
    fi

    echo "Applying custom configuration options to $config_path..."
    for option in "${CONFIG_OPTIONS[@]}"; do
        option_name=$(echo "$option" | cut -d'=' -f1)
        option_value=$(echo "$option" | cut -d'=' -f2)
        echo "Setting $option_name=$option_value"
        case $option_value in
            y) "$config_tool" --file "$config_path" --enable "$option_name" ;;
            m) "$config_tool" --file "$config_path" --module "$option_name" ;;
            # Add cases for string or int if needed, e.g.:
            # \"*) "$config_tool" --file "$config_path" --set-str "$option_name" "$(echo $option_value | sed 's/"//g')" ;;
            [0-9x]*) "$config_tool" --file "$config_path" --set-val "$option_name" "$option_value" ;;
            n) "$config_tool" --file "$config_path" --disable "$option_name" ;;
            *) echo "Warning: Unsupported option value type for $option_name: $option_value" ;;
        esac
    done

    # Handle LOCALVERSION
    local current_localversion=""
    if grep -q "^CONFIG_LOCALVERSION=" "$config_path"; then
        current_localversion=$(grep "^CONFIG_LOCALVERSION=" "$config_path" | cut -d'"' -f2)
    fi

    local new_localversion="${current_localversion}"
    # Check if the custom suffix pattern (e.g., -bkmz1) is already at the end
    if ! echo "${current_localversion}" | grep -q -- "-${CUSTOM_SUFFIX}$"; then
        # Append the custom suffix if it's not already there
        new_localversion="${current_localversion}-${CUSTOM_SUFFIX}"
    fi

    # Set the potentially updated LOCALVERSION
    if [ "${new_localversion}" != "${current_localversion}" ]; then
        echo "Updating CONFIG_LOCALVERSION to \"${new_localversion}\""
        "$config_tool" --file "$config_path" --set-str CONFIG_LOCALVERSION "${new_localversion}"
    else
        echo "CONFIG_LOCALVERSION already set to \"${current_localversion}\""
    fi

    # Clean up dependencies
    echo "Running olddefconfig to finalize configuration..."
    make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig KCONFIG_CONFIG="$config_path"
}


# Only handle config regeneration if requested
if [ "$REGEN_ONLY" -eq 1 ]; then
    echo "Regenerating .config file..."
    make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" bcm2712_defconfig

    # Apply custom options and update LOCALVERSION using the function
    apply_config_options "$KERNEL_DIR/.config"

    if [ "$ENABLE_LOCALMODCONFIG" -eq 1 ]; then
        echo "Running localmodconfig..."
        yes "" | make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" localmodconfig LSMOD=/home/bkmz/dev/uconsole/uconsole_patchset/lsmod_6.12.cm5
    fi

    echo "Config regeneration complete. Exiting."
    exit 0
fi

# Normal build process continues below
if [ ! -f "$KERNEL_DIR/.config" ]; then
    echo ".config file not found, running bcm2712_defconfig and localmodconfig if enabled"
    make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" bcm2712_defconfig

    # Apply custom options and update LOCALVERSION using the function
    apply_config_options "$KERNEL_DIR/.config"

    if [ "$ENABLE_LOCALMODCONFIG" -eq 1 ]; then
        make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" localmodconfig LSMOD=/home/bkmz/dev/uconsole/uconsole_patchset/lsmod_6.12.cm5
    fi

fi

# Ensure config options are applied even if .config existed
# This also handles LOCALVERSION update correctly
apply_config_options "$KERNEL_DIR/.config"

make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" modules

# Optional full build
if [ "$ENABLE_FULL_BUILD" -eq 1 ]; then
    make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" Image.gz dtbs
fi

make -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE"

rm -rf "$TARGET_DIR"

mkdir -p "$TARGET_DIR"

make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TARGET_DIR" modules_install

make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TARGET_DIR" install

echo "Copying kernel and device tree files..."
mkdir -p "$TARGET_DIR/boot/"
mkdir -p "$TARGET_DIR/boot/overlays"

if [ -f "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" ]; then
    cp "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" "$TARGET_DIR/boot/kernel_2712.img"
    cp "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" "$TARGET_DIR/boot/kernel.img"
else
    echo "Warning: Image.gz not found. You may need to enable ENABLE_FULL_BUILD."
fi

if [ -d "$KERNEL_DIR/arch/$ARCH/boot/dts/broadcom" ]; then
    cp "$KERNEL_DIR/arch/$ARCH/boot/dts/broadcom/"*.dtb "$TARGET_DIR/boot/"
fi

if [ -d "$KERNEL_DIR/arch/$ARCH/boot/dts/overlays" ]; then
    cp "$KERNEL_DIR/arch/$ARCH/boot/dts/overlays/"*.dtb* "$TARGET_DIR/boot/overlays/"
    cp "$KERNEL_DIR/arch/$ARCH/boot/dts/overlays/README" "$TARGET_DIR/boot/overlays/"
fi

# Get kernel version
KERNEL_VERSION=$(make -s -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)

# Install headers to version-specific directory
make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_HDR_PATH="$TARGET_DIR/usr/lib/modules/$KERNEL_VERSION/build" headers_install

if [ -d "overlays" ] && [ -n "$(ls -A overlays/*.dtbo 2>/dev/null)" ]; then
    cp overlays/*.dtbo "$TARGET_DIR/boot/overlays/"
    echo "Copied $(ls overlays/*.dtbo | wc -l) custom overlays to target directory"
fi

# Pack target directory into tar.gz archive
echo "Creating archive of target directory..."
pushd "$(dirname "$TARGET_DIR")" > /dev/null
tar czf "$ARCHIVE_NAME" "$(basename "$TARGET_DIR")"
popd > /dev/null

echo "Build completed successfully!"
echo "Created archive: $ARCHIVE_NAME"

echo "cd /"
echo "tar xvf PATH/$ARCHIVE_NAME --strip-components=1 --keep-directory-symlink"
echo "rsync -avHK --no-delete /path/to/target_dir/ pi@raspberry_pi_ip:/"

exit 0
