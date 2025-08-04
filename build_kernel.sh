#!/bin/bash
set -e

# =============================================================================
# uConsole Kernel Build Configuration
# =============================================================================

# Kernel source configuration
KERNEL_REPO="https://github.com/raspberrypi/linux.git"
KERNEL_VERSION=""                    # Auto-detect or specify (e.g., "6.6.62", "6.8.12")
KERNEL_BRANCH="rpi-6.12.y"          # Default branch if no version specified
KERNEL_BASE_DIR="kernels"           # Base directory for downloaded kernels
KERNEL_DIR=""                       # Will be set based on version/branch

# Platform configuration
PLATFORM="cm5"                      # cm4 or cm5
ARCH="arm64"                        # arm64 for CM4/5, arm for older
CROSS_COMPILE="aarch64-linux-gnu-"  # Cross compiler prefix

# Build configuration
JOBS=16
ENABLE_LOCALMODCONFIG=1          # Use localmodconfig to minimize kernel config based on loaded modules
ENABLE_FULL_BUILD=1              # Build full kernel (Image.gz + dtbs). If disabled, only builds external modules
REGEN_ONLY=0                     # Only regenerate .config file and exit (no actual kernel/module build)
CUSTOM_SUFFIX="bkmz1"            # Custom suffix appended to kernel version string
CONFIG_PROFILES=""               # Comma-separated list of config profiles to apply

# Skip options
SKIP_KERNEL_SETUP=0              # Skip kernel fetch/pull/clone operations
SKIP_CONFIG_CHANGES=0            # Skip all kernel config changes (except suffix increment)
SKIP_SUFFIX_INCREMENT=0          # Skip build suffix increment

# Build flow combinations:
# REGEN_ONLY=1: Generate/update .config → apply localmodconfig if enabled → EXIT (no build)
# REGEN_ONLY=0 + ENABLE_FULL_BUILD=1: Full build (kernel modules + Image.gz + dtbs + external modules)  
# REGEN_ONLY=0 + ENABLE_FULL_BUILD=0: Module-only build (kernel modules + external modules, no Image.gz/dtbs)

# Paths
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BUILD_STATE_DIR="${SCRIPT_DIR}/.build_state"
TARGET_DIR=""                           # Will be set based on platform: target/cm4 or target/cm5
ARCHIVE_NAME=""                         # Will be set based on platform and timestamp

# Platform-specific settings
declare -A PLATFORM_CONFIGS=(
    ["cm4"]="bcm2711_defconfig"
    ["cm5"]="bcm2712_defconfig"
)

declare -A PLATFORM_LSMOD=(
    ["cm4"]="/home/bkmz/dev/uconsole/uconsole_patchset/lsmod_6.12.cm4"
    ["cm5"]="/home/bkmz/dev/uconsole/uconsole_patchset/lsmod_6.12.cm5"
)

# =============================================================================
# Functions
# =============================================================================

setup_build_state_dir() {
    mkdir -p "$BUILD_STATE_DIR"
}

get_platform_build_counter() {
    local platform="$1"
    local counter_file="${BUILD_STATE_DIR}/${platform}_build_counter"
    
    if [ -f "$counter_file" ]; then
        cat "$counter_file"
    else
        echo "1"
    fi
}

increment_platform_counter() {
    local platform="$1"
    local counter_file="${BUILD_STATE_DIR}/${platform}_build_counter"
    local current_counter
    
    current_counter=$(get_platform_build_counter "$platform")
    local new_counter=$((current_counter + 1))
    echo "$new_counter" > "$counter_file"
    echo "$new_counter"
}

get_platform_last_kernel() {
    local platform="$1"
    local last_kernel_file="${BUILD_STATE_DIR}/${platform}_last_kernel"
    
    if [ -f "$last_kernel_file" ]; then
        cat "$last_kernel_file"
    else
        echo ""
    fi
}

set_platform_last_kernel() {
    local platform="$1"
    local kernel_dir="$2"
    local last_kernel_file="${BUILD_STATE_DIR}/${platform}_last_kernel"
    echo "$kernel_dir" > "$last_kernel_file"
}

validate_kernel_tree_for_platform() {
    local kernel_dir="$1"
    local target_platform="$2"
    
    if [ ! -d "$kernel_dir" ]; then
        return 0  # No kernel dir, nothing to validate
    fi
    
    if [ ! -f "$kernel_dir/.config" ]; then
        return 0  # No config file, tree is clean
    fi
    
    # Check if .config matches target platform
    local expected_defconfig="${PLATFORM_CONFIGS[$target_platform]}"
    if ! grep -q "CONFIG_ARCH_BCM2835=y" "$kernel_dir/.config" 2>/dev/null; then
        echo "Warning: Kernel tree may not be configured for Raspberry Pi platforms"
        return 1
    fi
    
    # Check for platform-specific markers
    case "$target_platform" in
        "cm4")
            # CM4 should not have CM5-specific configs
            if grep -q "CONFIG_ARCH_BCM2712=y" "$kernel_dir/.config" 2>/dev/null; then
                echo "Warning: Kernel tree appears to be configured for CM5 (BCM2712) but targeting CM4 (BCM2711)"
                return 1
            fi
            ;;
        "cm5")
            # CM5 should have BCM2712 support
            if grep -q "CONFIG_ARCH_BCM2711=y" "$kernel_dir/.config" 2>/dev/null && \
               ! grep -q "CONFIG_ARCH_BCM2712=y" "$kernel_dir/.config" 2>/dev/null; then
                echo "Warning: Kernel tree appears to be configured for CM4 (BCM2711) but targeting CM5 (BCM2712)"
                return 1
            fi
            ;;
    esac
    
    return 0
}

clean_kernel_tree_if_needed() {
    local kernel_dir="$1"
    local target_platform="$2"
    local force_clean="$3"
    
    if [ "$force_clean" = "true" ] || ! validate_kernel_tree_for_platform "$kernel_dir" "$target_platform"; then
        if [ -f "$kernel_dir/.config" ]; then
            echo "Cleaning kernel tree due to platform mismatch or force clean..."
            make -C "$kernel_dir" mrproper >/dev/null 2>&1 || true
            echo "Kernel tree cleaned successfully"
            return 1  # Indicate that cleaning was performed
        fi
    fi
    
    return 0  # No cleaning needed
}

setup_kernel_dir() {
    if [ -n "$KERNEL_VERSION" ]; then
        KERNEL_DIR="${SCRIPT_DIR}/${KERNEL_BASE_DIR}/rpi-${KERNEL_VERSION}-${PLATFORM}"
    else
        KERNEL_DIR="${SCRIPT_DIR}/${KERNEL_BASE_DIR}/$(basename "$KERNEL_BRANCH")-${PLATFORM}"
    fi
}

setup_target_paths() {
    # Set platform-specific target directory (same level as configs/ and kernels/)
    TARGET_DIR="${SCRIPT_DIR}/target/${PLATFORM}"
    
    # Archive name will be set later after kernel version is determined
}

increment_build_suffix() {
    setup_build_state_dir
    
    # Extract base suffix (remove any existing platform prefix and number)
    local base_suffix="$CUSTOM_SUFFIX"
    base_suffix="${base_suffix#*-}"  # Remove platform prefix if exists (e.g., "cm4-bkmz1" -> "bkmz1")
    base_suffix="${base_suffix%[0-9]*}"  # Remove number suffix (e.g., "bkmz1" -> "bkmz")
    
    # Get current counter for this platform
    local current_counter
    current_counter=$(get_platform_build_counter "$PLATFORM")
    
    # Check if we need to increment (only if building, not if just checking)
    local should_increment=true
    local last_kernel_dir
    last_kernel_dir=$(get_platform_last_kernel "$PLATFORM")
    
    if [ "$last_kernel_dir" = "$KERNEL_DIR" ] && [ -f "$KERNEL_DIR/.config" ]; then
        # Same kernel directory, check if we need to increment
        local existing_localversion
        if existing_localversion=$(grep '^CONFIG_LOCALVERSION=' "$KERNEL_DIR/.config" 2>/dev/null | cut -d'"' -f2); then
            local expected_suffix="${PLATFORM}-${base_suffix}-${current_counter}"
            if [[ "$existing_localversion" == *"-${expected_suffix}" ]]; then
                # Same version already exists, need to increment
                current_counter=$(increment_platform_counter "$PLATFORM")
                echo "Incrementing build counter for $PLATFORM: $((current_counter - 1)) → ${current_counter}"
            fi
        fi
    else
        # Different kernel directory or no existing config, increment counter
        current_counter=$(increment_platform_counter "$PLATFORM")
        echo "New build for $PLATFORM: using counter ${current_counter}"
    fi
    
    # Set the final suffix in the format: platform-base-counter
    CUSTOM_SUFFIX="${PLATFORM}-${base_suffix}-${current_counter}"
    echo "Using build suffix: ${CUSTOM_SUFFIX}"
    
    # Remember this kernel directory for this platform
    set_platform_last_kernel "$PLATFORM" "$KERNEL_DIR"
}

download_kernel() {
    local target_dir="$1"
    local branch_or_tag="$2"
    
    echo "Setting up kernel source in: $target_dir"
    
    if [ -d "$target_dir" ]; then
        echo "Kernel directory exists, updating..."
        cd "$target_dir"
        git fetch origin
        git checkout "$branch_or_tag"
        git pull origin "$branch_or_tag" 2>/dev/null || git reset --hard "$branch_or_tag"
    else
        echo "Cloning kernel repository..."
        mkdir -p "$(dirname "$target_dir")"
        git clone --depth=1 --branch="$branch_or_tag" "$KERNEL_REPO" "$target_dir"
    fi
    
    cd "$SCRIPT_DIR"
}

load_config_profile() {
    local profile_name="$1"
    local profile_path="${SCRIPT_DIR}/configs/${profile_name}.conf"
    
    if [ ! -f "$profile_path" ]; then
        echo "Error: Config profile '$profile_name' not found at $profile_path"
        return 1
    fi
    
    # Read config options from file, skip comments and empty lines
    grep -E '^CONFIG_' "$profile_path" | grep -v '^#'
}

apply_config_profiles() {
    local config_path="$1"
    local config_tool="${KERNEL_DIR}/scripts/config"
    local all_options=()
    
    if [ ! -f "$config_tool" ]; then
        echo "Error: Kernel config tool not found at $config_tool"
        exit 1
    fi
    if [ ! -f "$config_path" ]; then
        echo "Error: .config file not found at $config_path"
        exit 1
    fi

    # Apply configuration profiles only if not skipping config changes
    if [ "$SKIP_CONFIG_CHANGES" -eq 0 ]; then
        # Always apply base configuration first
        echo "Applying base configuration..."
        local base_options
        base_options=$(load_config_profile "base")
        if [ $? -ne 0 ]; then
            echo "Error: Failed to load base configuration"
            exit 1
        fi
        
        # Add base options to array
        while IFS= read -r option; do
            [ -n "$option" ] && all_options+=("$option")
        done <<< "$base_options"
        
        # Apply additional profiles if specified
        if [ -n "$CONFIG_PROFILES" ]; then
            echo "Applying additional config profiles: $CONFIG_PROFILES"
            IFS=',' read -ra PROFILES <<< "$CONFIG_PROFILES"
            for profile in "${PROFILES[@]}"; do
                profile=$(echo "$profile" | xargs)  # trim whitespace
                echo "Loading profile: $profile"
                
                local profile_options
                profile_options=$(load_config_profile "$profile")
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to load profile '$profile'"
                    exit 1
                fi
                
                # Add profile options to array
                while IFS= read -r option; do
                    [ -n "$option" ] && all_options+=("$option")
                done <<< "$profile_options"
            done
        fi
        
        # Apply all collected options
        echo "Applying $(( ${#all_options[@]} )) configuration options to $config_path..."
        for option in "${all_options[@]}"; do
            option_name=$(echo "$option" | cut -d'=' -f1)
            option_value=$(echo "$option" | cut -d'=' -f2)
            echo "Setting $option_name=$option_value"
            case $option_value in
                y) "$config_tool" --file "$config_path" --enable "$option_name" ;;
                m) "$config_tool" --file "$config_path" --module "$option_name" ;;
                [0-9x]*) "$config_tool" --file "$config_path" --set-val "$option_name" "$option_value" ;;
                n) "$config_tool" --file "$config_path" --disable "$option_name" ;;
                *) echo "Warning: Unsupported option value type for $option_name: $option_value" ;;
            esac
        done
    fi

    # Handle LOCALVERSION (suffix increment) only if not skipped
    if [ "$SKIP_SUFFIX_INCREMENT" -eq 0 ]; then
        local current_localversion=""
        if grep -q "^CONFIG_LOCALVERSION=" "$config_path"; then
            current_localversion=$(grep "^CONFIG_LOCALVERSION=" "$config_path" | cut -d'"' -f2)
        fi

        # Remove any existing platform-base-number suffix from current localversion
        local cleaned_localversion="$current_localversion"
        # Pattern matches: -{platform}-{base}-{number} (e.g., "-cm4-bkmz-1", "-cm5-bkmz-3")
        if [[ "$current_localversion" =~ -[^-]+-[^-]+-[0-9]+$ ]]; then
            # Remove the existing platform suffix (e.g., remove "-cm4-bkmz-1" from "-v8-16k-cm4-bkmz-1")
            cleaned_localversion=$(echo "$current_localversion" | sed 's/-[^-]*-[^-]*-[0-9]*$//')
        fi
        
        # Apply the new incremented suffix (CUSTOM_SUFFIX now contains platform-base-counter)
        local new_localversion="${cleaned_localversion}-${CUSTOM_SUFFIX}"

        # Set the updated LOCALVERSION
        if [ "${new_localversion}" != "${current_localversion}" ]; then
            echo "Updating CONFIG_LOCALVERSION: \"${current_localversion}\" → \"${new_localversion}\""
            "$config_tool" --file "$config_path" --set-str CONFIG_LOCALVERSION "${new_localversion}"
        else
            echo "CONFIG_LOCALVERSION already set to \"${current_localversion}\""
        fi
    else
        echo "Skipping build suffix increment in CONFIG_LOCALVERSION (--skip-suffix-increment)"
    fi

    # Clean up dependencies only if config changes were made
    if [ "$SKIP_CONFIG_CHANGES" -eq 0 ] || [ "$SKIP_SUFFIX_INCREMENT" -eq 0 ]; then
        echo "Running olddefconfig to finalize configuration..."
        make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig KCONFIG_CONFIG="$config_path"
    fi
}

show_help() {
    cat << EOF
Usage: $0 [options]

Kernel source options:
  --kernel-version VERSION    Specify kernel version (e.g., 6.6.62)
  --kernel-branch BRANCH      Specify kernel branch (e.g., rpi-6.6.y)
  --kernel-dir DIR            Use existing kernel directory

Platform options:
  --platform PLATFORM        Target platform: cm4 or cm5 (default: $PLATFORM)

Build options:
  --jobs N                    Number of parallel jobs (default: $JOBS)
  --custom-suffix SUFFIX      Custom kernel version suffix (default: $CUSTOM_SUFFIX)
  --config-profile PROFILES   Comma-separated config profiles (debug,minimal,performance,development,security)
  --regen-config              Regenerate .config and exit
  --enable-localmodconfig     Use localmodconfig (default)
  --disable-localmodconfig    Skip localmodconfig
  --enable-fullbuild          Enable full kernel build (default)
  --disable-fullbuild         Skip full kernel build

Skip options:
  --skip-kernel-setup         Skip kernel fetch/pull/clone operations
  --skip-config-changes       Skip all kernel config changes (except suffix increment)
  --skip-suffix-increment     Skip build suffix increment

Other options:
  -h, --help                  Show this help message

Examples:
  $0 --kernel-version 6.6.62 --platform cm5
  $0 --kernel-branch rpi-6.8.y --platform cm4 --jobs 8
  $0 --kernel-dir /path/to/existing/kernel --platform cm5
  $0 --platform cm5 --config-profile debug,development
  $0 --platform cm4 --config-profile minimal,performance
  $0 --platform cm5 --skip-kernel-setup --skip-config-changes
  $0 --platform cm5 --skip-kernel-setup --skip-suffix-increment
EOF
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --kernel-version) KERNEL_VERSION="$2"; shift ;;
        --kernel-branch) KERNEL_BRANCH="$2"; shift ;;
        --kernel-dir) KERNEL_DIR="$2"; shift ;;
        --platform) PLATFORM="$2"; shift ;;
        --jobs) JOBS="$2"; shift ;;
        --custom-suffix) CUSTOM_SUFFIX="$2"; shift ;;
        --config-profile) CONFIG_PROFILES="$2"; shift ;;
        --regen-config) REGEN_ONLY=1 ;;
        --enable-localmodconfig) ENABLE_LOCALMODCONFIG=1 ;;
        --disable-localmodconfig) ENABLE_LOCALMODCONFIG=0 ;;
        --enable-fullbuild) ENABLE_FULL_BUILD=1 ;;
        --disable-fullbuild) ENABLE_FULL_BUILD=0 ;;
        --skip-kernel-setup) SKIP_KERNEL_SETUP=1 ;;
        --skip-config-changes) SKIP_CONFIG_CHANGES=1 ;;
        --skip-suffix-increment) SKIP_SUFFIX_INCREMENT=1 ;;
        -h|--help) show_help; exit 0 ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# =============================================================================
# Setup and validation
# =============================================================================

# Validate platform
if [[ ! "${PLATFORM_CONFIGS[$PLATFORM]+isset}" ]]; then
    echo "Error: Unsupported platform '$PLATFORM'. Supported: ${!PLATFORM_CONFIGS[*]}"
    exit 1
fi

# Setup platform-specific paths
setup_target_paths

# Setup kernel directory if not specified
if [ -z "$KERNEL_DIR" ]; then
    setup_kernel_dir
fi

# Set platform-specific config
CONFIG_FILE="${KERNEL_DIR}/arch/${ARCH}/configs/${PLATFORM_CONFIGS[$PLATFORM]}"

echo "Configuration:"
echo "  Platform: $PLATFORM"
echo "  Architecture: $ARCH"
echo "  Kernel directory: $KERNEL_DIR"
echo "  Cross compiler: $CROSS_COMPILE"
echo "  Jobs: $JOBS"
echo ""

# Download/update kernel if needed
if [ "$SKIP_KERNEL_SETUP" -eq 0 ]; then
    if [ ! -d "$KERNEL_DIR" ] || [ -n "$KERNEL_VERSION" ] || [ -n "$KERNEL_BRANCH" ]; then
        if [ -n "$KERNEL_VERSION" ]; then
            echo "Using kernel version: $KERNEL_VERSION"
            download_kernel "$KERNEL_DIR" "v$KERNEL_VERSION"
        else
            echo "Using kernel branch: $KERNEL_BRANCH"
            download_kernel "$KERNEL_DIR" "$KERNEL_BRANCH"
        fi
    fi
else
    echo "Skipping kernel setup (--skip-kernel-setup)"
fi

# Validate kernel directory
if [ ! -d "$KERNEL_DIR" ]; then
    echo "Error: Kernel directory not found at $KERNEL_DIR"
    exit 1
fi

# Validate and clean kernel tree if needed for platform switch
echo "Validating kernel tree for platform $PLATFORM..."
if ! clean_kernel_tree_if_needed "$KERNEL_DIR" "$PLATFORM" "false"; then
    echo "Kernel tree validation and cleanup completed"
fi

# Increment build suffix based on existing config
if [ "$SKIP_SUFFIX_INCREMENT" -eq 0 ]; then
    increment_build_suffix "$KERNEL_DIR/.config"
else
    echo "Skipping build suffix increment (--skip-suffix-increment)"
fi

# =============================================================================
# Build Process
# =============================================================================


# Only handle config regeneration if requested
if [ "$REGEN_ONLY" -eq 1 ]; then
    if [ "$SKIP_CONFIG_CHANGES" -eq 0 ]; then
        echo "Regenerating .config file..."
        make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "${PLATFORM_CONFIGS[$PLATFORM]}"

        # Apply config profiles
        apply_config_profiles "$KERNEL_DIR/.config"

        if [ "$ENABLE_LOCALMODCONFIG" -eq 1 ]; then
            echo "Running localmodconfig for platform $PLATFORM..."
            if [ -f "${PLATFORM_LSMOD[$PLATFORM]}" ]; then
                yes "" | make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" localmodconfig LSMOD="${PLATFORM_LSMOD[$PLATFORM]}"
            else
                echo "Warning: LSMOD file not found: ${PLATFORM_LSMOD[$PLATFORM]}"
                echo "Skipping localmodconfig..."
            fi
        fi
    else
        echo "Skipping config changes (--skip-config-changes)"
        # Still apply suffix increment if not disabled
        if [ "$SKIP_SUFFIX_INCREMENT" -eq 0 ] && [ -f "$KERNEL_DIR/.config" ]; then
            apply_config_profiles "$KERNEL_DIR/.config"
        fi
    fi

    echo "Config regeneration complete. Exiting."
    exit 0
fi

# Normal build process continues below
if [ "$SKIP_CONFIG_CHANGES" -eq 0 ]; then
    if [ ! -f "$KERNEL_DIR/.config" ]; then
        echo ".config file not found, running ${PLATFORM_CONFIGS[$PLATFORM]} and localmodconfig if enabled"
        make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "${PLATFORM_CONFIGS[$PLATFORM]}"

        # Apply config profiles
        apply_config_profiles "$KERNEL_DIR/.config"

        if [ "$ENABLE_LOCALMODCONFIG" -eq 1 ]; then
            if [ -f "${PLATFORM_LSMOD[$PLATFORM]}" ]; then
                make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" localmodconfig LSMOD="${PLATFORM_LSMOD[$PLATFORM]}"
            else
                echo "Warning: LSMOD file not found: ${PLATFORM_LSMOD[$PLATFORM]}"
                echo "Skipping localmodconfig..."
            fi
        fi
    fi

    # Ensure config profiles are applied even if .config existed
    apply_config_profiles "$KERNEL_DIR/.config"
else
    echo "Skipping config changes (--skip-config-changes)"
    # Still apply suffix increment if not disabled and config exists
    if [ "$SKIP_SUFFIX_INCREMENT" -eq 0 ] && [ -f "$KERNEL_DIR/.config" ]; then
        apply_config_profiles "$KERNEL_DIR/.config"
    fi
fi

make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" modules

# Optional full build
if [ "$ENABLE_FULL_BUILD" -eq 1 ]; then
    make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" Image.gz dtbs
fi

make -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" PLATFORM="$PLATFORM" KDIR="$KERNEL_DIR"

rm -rf "$TARGET_DIR"

mkdir -p "$TARGET_DIR"

make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TARGET_DIR" modules_install

make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TARGET_DIR" PLATFORM="$PLATFORM" KDIR="$KERNEL_DIR" install

echo "Copying kernel and device tree files..."
mkdir -p "$TARGET_DIR/boot/"
mkdir -p "$TARGET_DIR/boot/overlays"

if [ -f "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" ]; then
    if [ "$PLATFORM" = "cm5" ]; then
        cp "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" "$TARGET_DIR/boot/kernel_2712.img"
    elif [ "$PLATFORM" = "cm4" ]; then
        cp "$KERNEL_DIR/arch/$ARCH/boot/Image.gz" "$TARGET_DIR/boot/kernel8.img"
    fi
    
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
KERNEL_RELEASE=$(make -s -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)

# Set archive name now that we have the kernel version
ARCHIVE_NAME="rpi_kernel_modules_${PLATFORM}_${KERNEL_RELEASE}_$(date +%Y%m%d_%H%M%S).tar.gz"

# Install headers to version-specific directory
make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" INSTALL_HDR_PATH="$TARGET_DIR/usr/lib/modules/$KERNEL_RELEASE/build" headers_install

if [ -d "overlays" ] && [ -n "$(ls -A overlays/*.dtbo 2>/dev/null)" ]; then
    cp overlays/*.dtbo "$TARGET_DIR/boot/overlays/"
    echo "Copied $(ls overlays/*.dtbo | wc -l) custom overlays to target directory"
fi

# Pack target directory into tar.gz archive
echo "Creating archive of target directory..."
pushd "$TARGET_DIR" > /dev/null
tar czf "../$ARCHIVE_NAME" .
popd > /dev/null

echo "Build completed successfully!"
echo "Platform: $PLATFORM"
echo "Kernel version: $KERNEL_RELEASE"
echo "Target directory: $TARGET_DIR"
echo "Created archive: $ARCHIVE_NAME"

echo ""
echo "Installation commands:"
echo "cd /"
echo "tar xvf PATH/$ARCHIVE_NAME --strip-components=1 --keep-directory-symlink"
echo "rsync -avHK --no-delete $TARGET_DIR/ pi@raspberry_pi_ip:/"

exit 0
