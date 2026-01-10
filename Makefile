#!/usr/bin/make -f

# =============================================================================
# uConsole Kernel Build Makefile
# =============================================================================
# Replaces complex build_kernel.sh with simpler, more maintainable approach
# Usage: make cm4, make cm5, make clean, make help

# Default platform if not specified
PLATFORM ?= cm5

# Kernel source configuration
KERNEL_REPO := https://github.com/raspberrypi/linux.git
KERNEL_VERSION ?= 
KERNEL_BRANCH ?= rpi-6.12.y
KERNEL_BASE_DIR := kernels
BUILD_STATE_DIR := .build_state

# Build configuration  
JOBS ?= 16
ARCH := arm64
CROSS_COMPILE := aarch64-linux-gnu-
CUSTOM_SUFFIX ?= bkmz
ENABLE_LOCALMODCONFIG ?= 1
ENABLE_FULL_BUILD ?= 1
CONFIG_PROFILES ?= 

# Skip options (can be overridden: make cm5 SKIP_KERNEL_SETUP=1)
SKIP_KERNEL_SETUP ?= 0
SKIP_CONFIG_CHANGES ?= 0
SKIP_SUFFIX_INCREMENT ?= 0

# Platform-specific configurations
CM4_DEFCONFIG := bcm2711_defconfig
CM5_DEFCONFIG := bcm2712_defconfig
CM4_LSMOD := /home/bkmz/dev/uconsole/uconsole_patchset/lsmod_6.12.cm4
CM5_LSMOD := /home/bkmz/dev/uconsole/uconsole_patchset/lsmod_6.12.cm5

# Derived variables based on platform
ifeq ($(PLATFORM),cm4)
    DEFCONFIG := $(CM4_DEFCONFIG)
    LSMOD_FILE := $(CM4_LSMOD)
    KERNEL_IMG := kernel8.img
else ifeq ($(PLATFORM),cm5)
    DEFCONFIG := $(CM5_DEFCONFIG)
    LSMOD_FILE := $(CM5_LSMOD)
    KERNEL_IMG := kernel_2712.img
else
    $(error Unsupported platform: $(PLATFORM). Use cm4 or cm5)
endif

# Set kernel directory based on version/branch and platform
ifdef KERNEL_VERSION
    KERNEL_DIR := $(KERNEL_BASE_DIR)/rpi-$(KERNEL_VERSION)-$(PLATFORM)
    KERNEL_TARGET := v$(KERNEL_VERSION)
else
    KERNEL_DIR := $(KERNEL_BASE_DIR)/$(shell basename $(KERNEL_BRANCH))-$(PLATFORM)
    KERNEL_TARGET := $(KERNEL_BRANCH)
endif

# Target and build paths
TARGET_DIR := target/$(PLATFORM)
BUILD_COUNTER_FILE := $(BUILD_STATE_DIR)/$(PLATFORM)_build_counter
LAST_KERNEL_FILE := $(BUILD_STATE_DIR)/$(PLATFORM)_last_kernel
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)

# Export KDIR for module builds (compatible with existing Makefile.modules)
export KDIR := $(realpath $(KERNEL_DIR))

# =============================================================================
# Helper Functions (using shell)
# =============================================================================

define get_build_counter
$(shell if [ -f "$(BUILD_COUNTER_FILE)" ]; then cat "$(BUILD_COUNTER_FILE)"; else echo "1"; fi)
endef

define increment_counter
$(shell current=$$(if [ -f "$(BUILD_COUNTER_FILE)" ]; then cat "$(BUILD_COUNTER_FILE)"; else echo "0"; fi); new=$$((current + 1)); echo "$$new" > "$(BUILD_COUNTER_FILE)"; echo "$$new")
endef

define get_last_kernel
$(shell if [ -f "$(LAST_KERNEL_FILE)" ]; then cat "$(LAST_KERNEL_FILE)"; else echo ""; fi)
endef

define set_last_kernel
$(shell echo "$(KERNEL_DIR)" > "$(LAST_KERNEL_FILE)")
endef

# =============================================================================
# Main Targets
# =============================================================================

.PHONY: cm4 cm5 clean help setup-build-state show-config validate-platform

# Platform-specific targets
cm4:
	@$(MAKE) PLATFORM=cm4 build-platform

cm5:
	@$(MAKE) PLATFORM=cm5 build-platform

# Main build target (internal)
build-platform: setup-build-state show-config validate-platform setup-kernel build-config build-kernel build-modules install-modules create-archive

# Setup and validation targets
setup-build-state:
	@mkdir -p $(BUILD_STATE_DIR)
	@mkdir -p $(dir $(KERNEL_DIR))

show-config:
	@echo "==================================================================="
	@echo "uConsole Kernel Build Configuration"
	@echo "==================================================================="
	@echo "Platform: $(PLATFORM)"
	@echo "Architecture: $(ARCH)" 
	@echo "Kernel directory: $(KERNEL_DIR)"
	@echo "Cross compiler: $(CROSS_COMPILE)"
	@echo "Jobs: $(JOBS)"
	@echo "Defconfig: $(DEFCONFIG)"
	@echo "Target directory: $(TARGET_DIR)"
	@echo "Build counter: $(call get_build_counter)"
	@echo "==================================================================="
	@echo

validate-platform:
	@if [ "$(PLATFORM)" != "cm4" ] && [ "$(PLATFORM)" != "cm5" ]; then \
		echo "Error: Unsupported platform '$(PLATFORM)'. Use cm4 or cm5"; \
		exit 1; \
	fi

# =============================================================================
# Kernel Setup and Validation
# =============================================================================

.PHONY: setup-kernel validate-kernel-tree clean-kernel-tree

setup-kernel:
	@if [ "$(SKIP_KERNEL_SETUP)" = "0" ]; then \
		echo "Setting up kernel source for $(PLATFORM)..."; \
		$(MAKE) -s setup-kernel-impl; \
	else \
		echo "Skipping kernel setup (SKIP_KERNEL_SETUP=1)"; \
	fi
	@$(MAKE) -s validate-kernel-tree

setup-kernel-impl:
	@if [ -d "$(KERNEL_DIR)" ]; then \
		echo "Kernel directory exists, updating..."; \
		cd "$(KERNEL_DIR)" && \
		git fetch origin && \
		git checkout "$(KERNEL_TARGET)" && \
		(git pull origin "$(KERNEL_TARGET)" 2>/dev/null || git reset --hard "$(KERNEL_TARGET)"); \
	else \
		echo "Cloning kernel repository..."; \
		git clone --depth=1 --branch="$(KERNEL_TARGET)" "$(KERNEL_REPO)" "$(KERNEL_DIR)"; \
	fi

validate-kernel-tree:
	@if [ ! -d "$(KERNEL_DIR)" ]; then \
		echo "Error: Kernel directory not found at $(KERNEL_DIR)"; \
		exit 1; \
	fi
	@echo "Validating kernel tree for platform $(PLATFORM)..."
	@$(MAKE) -s clean-kernel-tree-if-needed

clean-kernel-tree-if-needed:
	@if [ -f "$(KERNEL_DIR)/.config" ]; then \
		case "$(PLATFORM)" in \
			cm4) \
				if grep -q "CONFIG_ARCH_BCM2712=y" "$(KERNEL_DIR)/.config" 2>/dev/null; then \
					echo "Warning: Kernel tree configured for CM5 but targeting CM4, cleaning..."; \
					$(MAKE) -C "$(KERNEL_DIR)" mrproper >/dev/null 2>&1 || true; \
				fi ;; \
			cm5) \
				if grep -q "CONFIG_ARCH_BCM2711=y" "$(KERNEL_DIR)/.config" 2>/dev/null && \
				   ! grep -q "CONFIG_ARCH_BCM2712=y" "$(KERNEL_DIR)/.config" 2>/dev/null; then \
					echo "Warning: Kernel tree configured for CM4 but targeting CM5, cleaning..."; \
					$(MAKE) -C "$(KERNEL_DIR)" mrproper >/dev/null 2>&1 || true; \
				fi ;; \
		esac \
	fi

# =============================================================================
# Configuration Management
# =============================================================================

.PHONY: build-config apply-config-profiles increment-build-suffix

build-config:
	@if [ "$(SKIP_CONFIG_CHANGES)" = "0" ]; then \
		$(MAKE) -s build-config-impl; \
	else \
		echo "Skipping config changes (SKIP_CONFIG_CHANGES=1)"; \
	fi
	@$(MAKE) -s increment-build-suffix

build-config-impl:
	@echo "Configuring kernel for $(PLATFORM)..."
	@if [ ! -f "$(KERNEL_DIR)/.config" ]; then \
		echo "Creating initial .config with $(DEFCONFIG)"; \
		$(MAKE) -C "$(KERNEL_DIR)" -j$(JOBS) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(DEFCONFIG); \
	fi
	@if [ "$(ENABLE_LOCALMODCONFIG)" = "1" ] && [ -f "$(LSMOD_FILE)" ]; then \
		echo "Running localmodconfig for platform $(PLATFORM)..."; \
		yes "" | $(MAKE) -C "$(KERNEL_DIR)" -j$(JOBS) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) localmodconfig LSMOD="$(LSMOD_FILE)"; \
	elif [ "$(ENABLE_LOCALMODCONFIG)" = "1" ]; then \
		echo "Warning: LSMOD file not found: $(LSMOD_FILE), skipping localmodconfig"; \
	fi
	@$(MAKE) -s apply-config-profiles

apply-config-profiles:
	@if [ -n "$(CONFIG_PROFILES)" ]; then \
		echo "Applying config profiles: $(CONFIG_PROFILES)"; \
		$(MAKE) -s apply-profiles-impl; \
	fi
	@$(MAKE) -s apply-base-config

apply-base-config:
	@if [ -f "configs/base.conf" ]; then \
		echo "Applying base configuration..."; \
		$(MAKE) -s apply-single-profile PROFILE=base; \
	fi

apply-profiles-impl:
	@for profile in $(shell echo "$(CONFIG_PROFILES)" | tr ',' ' '); do \
		echo "Applying profile: $$profile"; \
		$(MAKE) -s apply-single-profile PROFILE=$$profile; \
	done

apply-single-profile:
	@if [ ! -f "configs/$(PROFILE).conf" ]; then \
		echo "Error: Config profile '$(PROFILE)' not found at configs/$(PROFILE).conf"; \
		exit 1; \
	fi
	@config_tool="$(KERNEL_DIR)/scripts/config"; \
	if [ ! -f "$$config_tool" ]; then \
		echo "Error: Kernel config tool not found at $$config_tool"; \
		exit 1; \
	fi; \
	grep -E '^CONFIG_' "configs/$(PROFILE).conf" | grep -v '^#' | while read option; do \
		option_name=$$(echo "$$option" | cut -d'=' -f1); \
		option_value=$$(echo "$$option" | cut -d'=' -f2); \
		case $$option_value in \
			y) "$$config_tool" --file "$(KERNEL_DIR)/.config" --enable "$$option_name" ;; \
			m) "$$config_tool" --file "$(KERNEL_DIR)/.config" --module "$$option_name" ;; \
			[0-9x]*) "$$config_tool" --file "$(KERNEL_DIR)/.config" --set-val "$$option_name" "$$option_value" ;; \
			n) "$$config_tool" --file "$(KERNEL_DIR)/.config" --disable "$$option_name" ;; \
			*) echo "Warning: Unsupported option value for $$option_name: $$option_value" ;; \
		esac; \
	done
	@$(MAKE) -C "$(KERNEL_DIR)" ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig

increment-build-suffix:
	@if [ "$(SKIP_SUFFIX_INCREMENT)" = "0" ]; then \
		$(MAKE) -s increment-build-suffix-impl; \
	else \
		echo "Skipping build suffix increment (SKIP_SUFFIX_INCREMENT=1)"; \
	fi

increment-build-suffix-impl:
	@echo "Managing build suffix for $(PLATFORM)..."
	@last_kernel="$(call get_last_kernel)"; \
	current_counter="$(call get_build_counter)"; \
	base_suffix=$$(echo "$(CUSTOM_SUFFIX)" | sed 's/^[^-]*-//' | sed 's/[0-9]*$$//'); \
	if [ "$$last_kernel" = "$(KERNEL_DIR)" ] && [ -f "$(KERNEL_DIR)/.config" ]; then \
		existing_localversion=$$(grep '^CONFIG_LOCALVERSION=' "$(KERNEL_DIR)/.config" 2>/dev/null | cut -d'"' -f2 || echo ""); \
		expected_suffix="$(PLATFORM)-$$base_suffix-$$current_counter"; \
		if echo "$$existing_localversion" | grep -q -- "-$$expected_suffix$$"; then \
			current_counter="$(call increment_counter)"; \
			echo "Incrementing build counter for $(PLATFORM): $$((current_counter - 1)) → $$current_counter"; \
		fi; \
	else \
		current_counter="$(call increment_counter)"; \
		echo "New build for $(PLATFORM): using counter $$current_counter"; \
	fi; \
	new_suffix="$(PLATFORM)-$$base_suffix-$$current_counter"; \
	echo "Using build suffix: $$new_suffix"; \
	config_tool="$(KERNEL_DIR)/scripts/config"; \
	current_localversion=$$(grep '^CONFIG_LOCALVERSION=' "$(KERNEL_DIR)/.config" 2>/dev/null | cut -d'"' -f2 || echo ""); \
	cleaned_localversion=$$(echo "$$current_localversion" | sed 's/-[^-]*-[^-]*-[0-9]*$$//'); \
	new_localversion="$$cleaned_localversion-$$new_suffix"; \
	if [ "$$new_localversion" != "$$current_localversion" ]; then \
		echo "Updating CONFIG_LOCALVERSION: \"$$current_localversion\" → \"$$new_localversion\""; \
		"$$config_tool" --file "$(KERNEL_DIR)/.config" --set-str CONFIG_LOCALVERSION "$$new_localversion"; \
	fi; \
	$(call set_last_kernel)

# =============================================================================
# Build Process
# =============================================================================

.PHONY: build-kernel build-modules install-modules create-archive

build-kernel:
	@echo "Building kernel modules..."
	@$(MAKE) -C "$(KERNEL_DIR)" -j$(JOBS) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	@if [ "$(ENABLE_FULL_BUILD)" = "1" ]; then \
		echo "Building full kernel (Image.gz + dtbs)..."; \
		$(MAKE) -C "$(KERNEL_DIR)" -j$(JOBS) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) Image.gz dtbs; \
	fi

build-modules:
	@echo "Building external modules..."
	@$(MAKE) -j$(JOBS) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) PLATFORM=$(PLATFORM) KDIR="$(KERNEL_DIR)" -f Makefile.modules
	@$(MAKE) -C "$(KERNEL_DIR)" M=$(PWD)/overlays KDIR="$(KERNEL_DIR)"

install-modules:
	@echo "Installing modules to target directory..."
	@rm -rf "$(TARGET_DIR)"
	@mkdir -p "$(TARGET_DIR)"
	@target_abs_path="$$(realpath $(TARGET_DIR))"; \
	echo "Installing kernel modules to $$target_abs_path..."; \
	$(MAKE) -C "$(KERNEL_DIR)" ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH="$$target_abs_path" modules_install; \
	echo "Installing external modules..."; \
	$(MAKE) -C "$(KERNEL_DIR)" M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH="$$target_abs_path" modules_install; \
	$(MAKE) -C "$(KERNEL_DIR)" M=$(PWD)/overlays ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH="$$target_abs_path" modules_install; \
	echo "Installing kernel headers..."; \
	$(MAKE) -C "$(KERNEL_DIR)" ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_HDR_PATH="$$target_abs_path/usr" headers_install
	@$(MAKE) -s install-kernel-files

install-kernel-files:
	@echo "Copying kernel and device tree files..."
	@mkdir -p "$(TARGET_DIR)/boot/overlays"
	@if [ -f "$(KERNEL_DIR)/arch/$(ARCH)/boot/Image.gz" ]; then \
		cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/Image.gz" "$(TARGET_DIR)/boot/$(KERNEL_IMG)"; \
	else \
		echo "Warning: Image.gz not found. Enable ENABLE_FULL_BUILD=1 for full kernel build."; \
	fi
	@if [ -d "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/broadcom" ]; then \
		cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/broadcom/"*.dtb "$(TARGET_DIR)/boot/" 2>/dev/null || true; \
	fi
	@if [ -d "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/overlays" ]; then \
		cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/overlays/"*.dtb* "$(TARGET_DIR)/boot/overlays/" 2>/dev/null || true; \
		cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/overlays/README" "$(TARGET_DIR)/boot/overlays/" 2>/dev/null || true; \
	fi
	@if [ -d "overlays" ] && [ -n "$$(ls -A overlays/*.dtbo 2>/dev/null)" ]; then \
		cp overlays/*.dtbo "$(TARGET_DIR)/boot/overlays/"; \
		echo "Copied $$(ls overlays/*.dtbo 2>/dev/null | wc -l) custom overlays"; \
	fi

create-archive:
	@echo "Creating deployment archive..."
	@kernel_release=$$($(MAKE) -s -C "$(KERNEL_DIR)" ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) kernelrelease 2>/dev/null || echo "unknown"); \
	timestamp=$$(date +%Y%m%d_%H%M%S); \
	archive_name="rpi_kernel_modules_$(PLATFORM)_$${kernel_release}_$${timestamp}.tar.gz"; \
	archive_path="$$(realpath .)/$$archive_name"; \
	target_path="$$(realpath $(TARGET_DIR))"; \
	echo "Kernel release: $$kernel_release"; \
	echo "Archive name: $$archive_name"; \
	echo "Creating archive: $$archive_name"; \
	cd "$(TARGET_DIR)" && tar czf "../$$archive_name" .; \
	echo ""; \
	echo "Build completed successfully!"; \
	echo "Platform: $(PLATFORM)"; \
	echo "Kernel version: $$kernel_release"; \
	echo "Target directory: $$target_path"; \
	echo "Created archive: $$archive_path"; \
	echo ""; \
	echo "Installation commands:"; \
	echo "cd /"; \
	echo "tar xvf $$archive_path --strip-components=1 --keep-directory-symlink"; \
	echo "rsync -avHK --no-delete $$target_path/ pi@raspberry_pi_ip:/"

# =============================================================================
# Clean Targets
# =============================================================================

.PHONY: clean clean-kernel clean-all

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf target/
	@rm -rf $(BUILD_STATE_DIR)
	@if [ -f "Makefile.modules" ]; then $(MAKE) -f Makefile.modules clean KDIR="$(KERNEL_DIR)" 2>/dev/null || true; fi
	@echo "Clean completed."

clean-kernel:
	@echo "Cleaning kernel trees..."
	@rm -rf $(KERNEL_BASE_DIR)/
	@echo "Kernel trees cleaned."

clean-all: clean clean-kernel

# =============================================================================
# Help Target
# =============================================================================

help:
	@echo "uConsole Kernel Build System"
	@echo ""
	@echo "Main targets:"
	@echo "  cm4                    Build kernel and modules for CM4 platform"
	@echo "  cm5                    Build kernel and modules for CM5 platform"
	@echo ""
	@echo "Configuration options (use KEY=VALUE):"
	@echo "  PLATFORM=cm4|cm5      Target platform (default: cm5)"
	@echo "  JOBS=N                 Number of parallel jobs (default: 16)"
	@echo "  KERNEL_VERSION=X.Y.Z   Specific kernel version to use"
	@echo "  KERNEL_BRANCH=branch   Kernel branch to use (default: rpi-6.12.y)"
	@echo "  CUSTOM_SUFFIX=suffix   Custom version suffix (default: bkmz)"
	@echo "  CONFIG_PROFILES=list   Comma-separated config profiles"
	@echo ""
	@echo "Build options:"
	@echo "  ENABLE_LOCALMODCONFIG=0|1    Use localmodconfig (default: 1)"
	@echo "  ENABLE_FULL_BUILD=0|1        Build full kernel (default: 1)"
	@echo ""
	@echo "Skip options:"
	@echo "  SKIP_KERNEL_SETUP=1    Skip kernel fetch/setup"
	@echo "  SKIP_CONFIG_CHANGES=1  Skip config modifications"
	@echo "  SKIP_SUFFIX_INCREMENT=1 Skip build counter increment"
	@echo ""
	@echo "Clean targets:"
	@echo "  clean                  Remove build artifacts and state"
	@echo "  clean-kernel           Remove downloaded kernel trees"
	@echo "  clean-all              Remove everything"
	@echo ""
	@echo "Examples:"
	@echo "  make cm5               # Build for CM5 with defaults"
	@echo "  make cm4 JOBS=8        # Build for CM4 with 8 parallel jobs"
	@echo "  make cm5 KERNEL_VERSION=6.6.62"
	@echo "  make cm4 CONFIG_PROFILES=debug,development"
	@echo "  make cm5 SKIP_KERNEL_SETUP=1"
	@echo "  make cm4 ENABLE_FULL_BUILD=0    # Module-only build"