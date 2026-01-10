# uConsole Kernel Build System

A simplified, maintainable kernel build system for ClockworkPi uConsole devices (CM4/CM5) with required DT overlays, screen and backlight modules.

## Project Goals

### Primary Objectives
- Create a centralized repository for all uConsole-specific drivers
- Enable mainline Linux kernel usage without patches or modifications  
- Document known kernel/driver level issues
- Lower the barrier to entry for custom kernel building

### Technical Approach
- Use external modules and device tree overlays instead of kernel tree modifications
- Maintain complete change history for all drivers
- Support multiple Linux distributions from a single source

### Long-term Vision
- Make a simple Alpine Linux image that you just dd and it boots
- Make simple .deb packages for uConsole in a dedicated apt repo. Maybe provide solutions for other distros too.


## TODO 

- Add proper profiles and test their config options
- Get latest firmware for rpi and store it in /boot
- Have some necessary adjustments for config.txt, cmdline in that repo to have a fully functional system after building
- Document A/B autoboot rpi feature for almost failsafe testing
- Support for CM3
- Support for devterm

- (optional) maybe for the sake of tests make a small buildroot system? or small busybox in initramfs? 

## Why This Project Exists

Building custom kernels for uConsole devices was unnecessarily complex:

### The Problem with Existing Solutions
All known repositories used for uConsole kernel development require complex merges because panel driver (cwu50) and backlight (ocp8178) drivers live in the kernel tree. This creates several issues:
- **Merge conflicts** when updating to newer kernel versions
- **Patch maintenance** burden across kernel updates  
- **Limited flexibility** to test different kernel versions quickly

### Key Innovation
Unlike existing uConsole kernel repositories that require merging patches into the kernel tree, this project maintains **clean separation** between:
- **Mainline Raspberry Pi Linux kernel** (completely unmodified)
- **uConsole-specific drivers** (as external modules)  
- **Hardware configuration** (as device tree overlays)

This approach provides:
- **Easier maintenance**: No complex merges or patch conflicts
- **Broader compatibility**: Works with any kernel version
- **Cleaner testing**: Simple rsync deployment workflow

### Simple Testing Workflow
1. Build kernel
2. rsync prepared artifacts to the running uConsole
3. Boot and test
4. If boot fails, manually restore previous kernel and device tree overlays from backup

*Note: A safer approach using the Raspberry Pi `tryboot` feature is documented in our TODO list.*


## What Makes This Better

### ✨ **Simplicity**
- **Zero external dependencies** - Uses only standard Linux tools (Make, GCC). If you can already cross-compile the Linux kernel, you have all the necessary dependencies.

- **Simple commands** - `make cm4` or `make cm5` is all you need, and you will get a complete set of kernel, device tree overlays, and modules compiled and prepared to be transferred to your uConsole.

## Features

- **Multi-platform support** - CM4 and CM5 with automatic configuration for uConsole
- **Integrated module building** - Kernel modules, external modules, and device tree overlays
- **Additional versioning** - Platform-aware build counters (e.g., `cm4-bkmz-1`, `cm5-bkmz-3`), or your personal suffix in kernel name
- **Complete deployment** - Generates ready-to-install archives with all components
- **Complete kernel modules** - Kernels include all modules from the platform defconfig, ensuring full compatibility (TUN/TAP, networking, etc.) out of the box.

## Quick Start

### Basic Usage

```bash
# Build for CM5 (default)
make cm5

# Build for CM4  
make cm4

# Clean build artifacts
make clean
```

## Configuration

### Platform Options
- `PLATFORM=cm4|cm5` - Target platform (default: cm5)
- `JOBS=N` - Parallel build jobs (default: 16)
- `KERNEL_VERSION=X.Y.Z` - Specific kernel version
- `KERNEL_BRANCH=branch` - Kernel branch (default: rpi-6.12.y)

### Build Options
- `--force-clean` - Force .config regeneration from defconfig
- `ENABLE_FULL_BUILD=0|1` - Build full kernel (default: 1)
- `CONFIG_PROFILES=list` - Comma-separated config profiles (debug, minimal, performance, development, security)
- `CUSTOM_SUFFIX=suffix` - Custom version suffix (default: bkmz)

### Skip Options
- `SKIP_KERNEL_SETUP=1` - Skip kernel fetch/setup
- `SKIP_CONFIG_CHANGES=1` - Skip config modifications
- `SKIP_SUFFIX_INCREMENT=1` - Skip build counter increment

## Configuration Management

The build system now uses a cleaner configuration approach:

- **Default Configuration**: Kernels use the complete bcm2711_defconfig or bcm2712_defconfig, ensuring all standard kernel modules are available (TUN/TAP, networking, etc.)
- **Configuration Profiles**: Optional profiles in `configs/` directory can further customize the kernel (debug, development, performance, minimal, security)
- **Force Clean**: Use `--force-clean` flag to regenerate `.config` from defconfig and remove any stale configuration from previous builds
- **Automatic Platform Detection**: Switching between CM4 and CM5 is automatically detected and handled with a clean rebuild when needed

## Supported Drivers

This repository includes drivers for:

- **Power Management** - AXP20X AC/USB power, battery monitoring
- **Display** - ClockworkPi CWU50 panel drivers for CM4/CM5  
- **Backlight** - OCP8178 backlight controllers
- **Device Tree Overlays** - Complete uConsole hardware support

## Development Roadmap

### Driver Development
- **AXP20X drivers**: Improve PMIC drivers for better userspace support and expose more hardware features to end users
- **CWU50 panel**: Consolidate many different existing versions of the CWU driver in one place
- **Device Tree Overlays**: Create modular, single-purpose overlay files for easy configuration. For example, since Ethernet is not wired on uConsole CM modules, it should be completely disabled via device tree overlay. The goal is to have a folder of device tree overlays with only one simple function per DTS file, making it much easier for end users to configure their devices. 

## Installation

- `WIP`

## ⚠️ Important Safety Notes

**Testing Warning**: Since testing requires deploying to actual uConsole hardware, your device may fail to boot. Always:
- Keep a backup of your working kernel and device tree overlays
- Be prepared to manually restore from microSD card
- Consider using the Raspberry Pi `tryboot` feature for safer testing (documented in TODO)

## License

[License information to be added]

---

**Note**: This project is in early development. While functional, expect frequent updates and improvements. Always test builds before deploying to your main uConsole device!