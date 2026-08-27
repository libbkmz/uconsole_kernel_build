SHELL := /bin/bash

KERNEL_BRANCH ?= rpi-6.12.y
KERNEL_REPO   ?= https://github.com/raspberrypi/linux.git
JOBS          ?= $(shell getconf _NPROCESSORS_ONLN)
PROFILES      ?=

ARCH := arm64
CROSS_COMPILE ?= $(shell [ "$$(uname -m)" = aarch64 ] || printf aarch64-linux-gnu-)

BUILD_DIR  := $(CURDIR)/build/$(PLATFORM)
KERNEL_DIR := $(BUILD_DIR)/linux
STAGE_DIR  := $(BUILD_DIR)/stage
DIST_DIR   := $(CURDIR)/dist
BOOT_DIR   := boot/firmware
CONFIGS    := $(CURDIR)/configs/base.conf $(addprefix $(CURDIR)/configs/,$(addsuffix .conf,$(PROFILES)))

ifeq ($(PLATFORM),cm4)
DEFCONFIG  := bcm2711_defconfig
KERNEL_IMG := kernel8.img
DTB_PREFIX := bcm2711
OVERLAY    := clockworkpi-uconsole-overlay.dtbo
BOOT_CONFIG := configs/cm4.config.txt
MODULES    := panel-cwu50 ocp8178_bl
endif
ifeq ($(PLATFORM),cm5)
DEFCONFIG  := bcm2712_defconfig
KERNEL_IMG := kernel_2712.img
DTB_PREFIX := bcm2712
OVERLAY    := clockworkpi-uconsole-cm5-overlay.dtbo
BOOT_CONFIG := configs/cm5.config.txt
MODULES    := panel-clockwork-cwu50 panel-cwu50-nova-cm5 panel-cwu50-rex-cm5 ocp8178_bl-nova-cm5
endif

MAKE_KERNEL = $(MAKE) -C "$(KERNEL_DIR)" -j$(JOBS) \
	ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) LOCALVERSION=-uconsole-$(PLATFORM)

.PHONY: help deps cm4 cm5 check configure build archive clean

help:
	@echo "make deps       install Debian/Ubuntu build tools"
	@echo "make cm4        build a safe-to-extract CM4 archive"
	@echo "make cm5        build a safe-to-extract CM5 archive"
	@echo "make clean      remove clones and build results"

deps:
	sudo apt-get update
	sudo apt-get install -y build-essential git bc flex bison libssl-dev libelf-dev \
		device-tree-compiler $(if $(CROSS_COMPILE),gcc-aarch64-linux-gnu)

cm4 cm5:
	$(MAKE) PLATFORM=$@ archive

check:
	@test -n "$(DEFCONFIG)" || { echo "Use make cm4 or make cm5" >&2; exit 2; }

$(KERNEL_DIR)/.git:
	mkdir -p "$(BUILD_DIR)"
	git clone --depth 1 --branch "$(KERNEL_BRANCH)" "$(KERNEL_REPO)" "$(KERNEL_DIR)"

configure: check $(KERNEL_DIR)/.git
	$(MAKE_KERNEL) $(DEFCONFIG)
	cd "$(KERNEL_DIR)" && scripts/kconfig/merge_config.sh -m -O . .config $(CONFIGS)
	$(MAKE_KERNEL) olddefconfig

build: configure
	$(MAKE_KERNEL) M="$(CURDIR)/src" PLATFORM=$(PLATFORM) clean
	$(MAKE_KERNEL) M="$(CURDIR)/overlays" KDIR="$(KERNEL_DIR)" PLATFORM=$(PLATFORM) clean
	$(MAKE_KERNEL) Image.gz modules dtbs
	$(MAKE_KERNEL) M="$(CURDIR)/src" PLATFORM=$(PLATFORM) modules
	$(MAKE_KERNEL) M="$(CURDIR)/overlays" KDIR="$(KERNEL_DIR)" PLATFORM=$(PLATFORM)

archive: build
	@set -eu; \
	release="$$($(MAKE_KERNEL) -s kernelrelease)"; \
	name="uconsole-$(PLATFORM)-$${release}-$$(date +%Y%m%d_%H%M%S)"; \
	root="$(STAGE_DIR)/$$name"; \
	rm -rf "$(STAGE_DIR)"; \
	mkdir -p "$$root/$(BOOT_DIR)/overlays" "$(DIST_DIR)"; \
	$(MAKE_KERNEL) INSTALL_MOD_PATH="$$root" modules_install; \
	$(MAKE_KERNEL) M="$(CURDIR)/src" PLATFORM=$(PLATFORM) INSTALL_MOD_PATH="$$root" modules_install; \
	rm -f "$$root/lib/modules/$$release/build" "$$root/lib/modules/$$release/source"; \
	cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/Image.gz" "$$root/$(BOOT_DIR)/$(KERNEL_IMG)"; \
	cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/broadcom/$(DTB_PREFIX)-"*.dtb "$$root/$(BOOT_DIR)/"; \
	cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/overlays/"*.dtb* "$$root/$(BOOT_DIR)/overlays/"; \
	cp "$(KERNEL_DIR)/arch/$(ARCH)/boot/dts/overlays/README" "$$root/$(BOOT_DIR)/overlays/"; \
	cp "$(CURDIR)/overlays/$(OVERLAY)" "$$root/$(BOOT_DIR)/overlays/"; \
	cp "$(KERNEL_DIR)/.config" "$$root/$(BOOT_DIR)/config-$$release"; \
	cp "$(KERNEL_DIR)/System.map" "$$root/$(BOOT_DIR)/System.map-$$release"; \
	cp "$(CURDIR)/$(BOOT_CONFIG)" "$$root/$(BOOT_DIR)/config.txt.additions"; \
	for module in $(MODULES); do test -n "$$(find "$$root/lib/modules/$$release" -name "$$module.ko*" -print -quit)"; done; \
	test -n "$$(find "$$root/$(BOOT_DIR)" -maxdepth 1 -name '$(DTB_PREFIX)-*.dtb' -print -quit)"; \
	test -f "$$root/$(BOOT_DIR)/overlays/$(OVERLAY)"; \
	test -f "$$root/$(BOOT_DIR)/overlays/README"; \
	tar -C "$(STAGE_DIR)" -czf "$(DIST_DIR)/$$name.tar.gz" "$$name"; \
	tar tzf "$(DIST_DIR)/$$name.tar.gz" | awk -v root="$$name/" 'index($$0, root) != 1 { exit 1 }'; \
	tar tvzf "$(DIST_DIR)/$$name.tar.gz" | awk '$$1 ~ /^l/ { exit 1 }'; \
	echo "$(DIST_DIR)/$$name.tar.gz"

clean:
	rm -rf "$(CURDIR)/build" "$(CURDIR)/dist"
