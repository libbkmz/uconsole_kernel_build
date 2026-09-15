#!/usr/bin/env bash
set -euo pipefail
trap 'printf "package.sh:%s: failed: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Called by make package after the kernel and external modules are built.
repo=$(cd "$(dirname "$0")/.." && pwd)
kernel=$(cd "$KERNEL_DIR" && pwd)
release=$(make -s -C "$kernel" kernelrelease)
[[ ${#release} -le 64 ]] || { echo "Kernel release exceeds 64 characters" >&2; exit 1; }
export KDEB_PKGVERSION="$VERSION" KBUILD_DEBARCH=arm64
export DEBFULLNAME="${DEBFULLNAME:-uConsole builder}"
export DEBEMAIL="${DEBEMAIL:-uconsole@localhost}"

# Use the upstream image/header builders, without libc headers or debug packages.
# "debian" is internal to scripts/Makefile.package, not a top-level target.
make -C "$kernel" run-command KBUILD_RUN_COMMAND='$(srctree)/scripts/package/mkdebian'
make -C "$kernel" -f debian/rules -j"$JOBS" binary-image binary-headers

stage="$repo/build/cm4/packages"
dist="$repo/dist/$VERSION"
rm -rf "$stage"
mkdir -p "$stage" "$dist"
for kind in image headers; do
    dpkg-deb --raw-extract "$kernel/../linux-${kind}-${release}_${VERSION}_arm64.deb" "$stage/$kind"
done

image="$stage/image"
headers="$stage/headers"
modules="$image/lib/modules/$release"
make -C "$kernel" M="$repo/src" PLATFORM=cm4 INSTALL_MOD_PATH="$image" INSTALL_MOD_STRIP=1 modules_install
rm -f "$modules/build" "$modules/source"

# Match Raspberry Pi OS's versioned DTB layout; boot-partition copying is deferred.
mv "$image/usr/lib/linux-image-$release" "$modules/dtb"
cp "$kernel/arch/arm64/boot/dts/overlays/README" "$modules/dtb/overlays/"
cp "$repo/overlays/clockworkpi-uconsole-overlay.dtbo" "$modules/dtb/overlays/"
depmod -b "$image" "$release"

doc="$image/usr/share/doc/uconsole-kernel-cm4"
mkdir -p "$doc"
cp "$repo/configs/cm4.config.txt" "$doc/config.txt.example"
git -C "$kernel" rev-parse HEAD > "$doc/kernel-commit"
cp "$kernel/.config" "$dist/kernel.config"
cp "$doc/kernel-commit" "$dist/kernel-commit"

# Keep upstream maintainer scripts and header build tree; replace package metadata.
for kind in image headers; do
    root="$stage/$kind"
    name=uconsole-kernel-cm4
    depends='kmod, initramfs-tools, raspi-firmware'
    description='CM4 uConsole kernel, modules and device trees'
    if [[ $kind == headers ]]; then
        name=uconsole-kernel-headers-cm4
        depends="uconsole-kernel-cm4 (= $VERSION), make, gcc, libc6-dev, libssl-dev"
        description='Headers and build files for the matching CM4 uConsole kernel'
    fi
    cat > "$root/DEBIAN/control" <<EOF
Package: $name
Version: $VERSION
Architecture: arm64
Maintainer: $DEBFULLNAME <$DEBEMAIL>
Section: kernel
Priority: optional
Depends: $depends
Installed-Size: $(du -sk --exclude=DEBIAN "$root" | cut -f1)
Description: $description
 Kernel release: $release
EOF
    # External modules and overlays changed the upstream package contents.
    (cd "$root" && find . -path ./DEBIAN -prune -o -type f -print0 | \
        LC_ALL=C sort -z | xargs -0 md5sum) > "$root/DEBIAN/md5sums"
done

# Fail before publishing an incomplete pair. These checks run on the build server.
test -s "$image/boot/vmlinuz-$release"
test -s "$image/boot/config-$release"
# Raspberry Pi kernels may install DTBs flat or grouped by vendor.
test -s "$modules/dtb/bcm2711-rpi-cm4.dtb" || test -s "$modules/dtb/broadcom/bcm2711-rpi-cm4.dtb"
test -s "$modules/dtb/overlays/clockworkpi-uconsole-overlay.dtbo"
for module in panel-cwu50 ocp8178_bl; do
    test -n "$(find "$modules" -name "$module.ko*" -print -quit)"
done
test -s "$headers/usr/src/linux-headers-$release/Module.symvers"
test -s "$headers/usr/src/linux-headers-$release/include/generated/autoconf.h"
test "$(readlink "$headers/lib/modules/$release/build")" = "/usr/src/linux-headers-$release"
for script in preinst postinst prerm postrm; do
    test -x "$image/DEBIAN/$script"
done

dpkg-deb --root-owner-group --build "$image" "$dist/uconsole-kernel-cm4_${VERSION}_arm64.deb"
dpkg-deb --root-owner-group --build "$headers" "$dist/uconsole-kernel-headers-cm4_${VERSION}_arm64.deb"
echo "Packages: $dist"
