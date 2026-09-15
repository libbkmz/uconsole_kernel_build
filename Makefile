SHELL := /bin/bash
.DEFAULT_GOAL := help

KERNEL_REPO ?= https://github.com/raspberrypi/linux.git
KERNEL_REF  ?= rpi-6.12.y
KERNEL_DIR ?= $(CURDIR)/build/cm4/linux
JOBS       ?= $(shell getconf _NPROCESSORS_ONLN)
VERSION    := $(or $(VERSION),$(shell date -u +%Y%m%d%H%M%S))
CROSS_COMPILE ?= $(shell [ "$$(uname -m)" = aarch64 ] || printf aarch64-linux-gnu-)

export KERNEL_DIR JOBS VERSION CROSS_COMPILE
export ARCH := arm64
export LOCALVERSION := -uconsole-$(VERSION)-rpi-v8
MAKE_KERNEL = $(MAKE) -C "$(KERNEL_DIR)" -j$(JOBS)

.PHONY: help deps source update configure build package cm4 clean

help:
	@echo "make deps       install Debian/Trixie build tools"
	@echo "make cm4        build kernel and headers debs in dist/<version>/"
	@echo "make update     fetch and select KERNEL_REF (requires a clean source tree)"
	@echo "Edit configs/uconsole.conf; use VERSION=<increasing number> for a release."

deps:
	$(if $(CROSS_COMPILE),sudo dpkg --add-architecture arm64,:)
	sudo apt-get update
	sudo apt-get install -y build-essential git bc flex bison libssl-dev libelf-dev \
		device-tree-compiler debhelper dpkg-dev cpio kmod rsync python3 \
		$(if $(CROSS_COMPILE),gcc-aarch64-linux-gnu libssl-dev:arm64)

source:
	@test -d "$(KERNEL_DIR)/.git" || { \
		git clone --depth 1 --no-checkout "$(KERNEL_REPO)" "$(KERNEL_DIR)" && \
		git -C "$(KERNEL_DIR)" fetch --depth 1 origin "$(KERNEL_REF)" && \
		git -C "$(KERNEL_DIR)" checkout --detach FETCH_HEAD && \
		git -C "$(KERNEL_DIR)" config uconsole.ref "$(KERNEL_REF)"; }
	@test -f "$(KERNEL_DIR)/Makefile"
	@ref="$$(git -C "$(KERNEL_DIR)" config --get uconsole.ref || true)"; \
		[[ -z "$$ref" || "$$ref" = "$(KERNEL_REF)" ]] || \
		{ echo "KERNEL_REF changed; run make update first" >&2; exit 1; }

update:
	@test -z "$$(git -C "$(KERNEL_DIR)" status --porcelain --untracked-files=no)" || \
		{ echo "Kernel source has local changes" >&2; exit 1; }
	git -C "$(KERNEL_DIR)" fetch --depth 1 origin "$(KERNEL_REF)"
	git -C "$(KERNEL_DIR)" checkout --detach FETCH_HEAD
	git -C "$(KERNEL_DIR)" config uconsole.ref "$(KERNEL_REF)"

configure: source
	@[[ "$(VERSION)" =~ ^[0-9]+([.][0-9]+)*$$ ]] || { echo "VERSION must contain numbers separated by dots" >&2; exit 1; }
	$(MAKE_KERNEL) bcm2711_defconfig
	cd "$(KERNEL_DIR)" && scripts/kconfig/merge_config.sh -m .config "$(CURDIR)/configs/uconsole.conf"
	$(MAKE_KERNEL) olddefconfig

build: configure
	$(MAKE_KERNEL) M="$(CURDIR)/src" PLATFORM=cm4 clean
	$(MAKE_KERNEL) M="$(CURDIR)/overlays" KDIR="$(KERNEL_DIR)" PLATFORM=cm4 clean
	$(MAKE_KERNEL) Image.gz modules dtbs
	$(MAKE_KERNEL) M="$(CURDIR)/src" PLATFORM=cm4 modules
	$(MAKE_KERNEL) M="$(CURDIR)/overlays" KDIR="$(KERNEL_DIR)" PLATFORM=cm4

package: build
	bash scripts/package.sh

cm4: package

clean:
	rm -rf "$(CURDIR)/build" "$(CURDIR)/dist"
