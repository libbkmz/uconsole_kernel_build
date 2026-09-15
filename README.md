# uConsole kernel packages

Build CM4 kernel and matching headers packages for Raspberry Pi OS Trixie
64-bit, on a Debian Trixie arm64 or amd64 build server. CM5 sources are retained
but this package workflow currently targets CM4 only.

## Build

```console
make deps
make cm4
```

Edit `configs/uconsole.conf` to change kernel options. Each build starts from
Raspberry Pi's `bcm2711_defconfig` and applies that file. Direct edits to the
generated `.config` are overwritten. Display/backlight drivers stay out of
tree and are always included.

`VERSION` defaults to a UTC timestamp. You can supply an increasing numeric
version (digits and dots only):

```console
make cm4 VERSION=2026091601
```

Use a new, higher version for every published build, including config-only
changes. Both packages have stable names, so upgrading replaces the previous
package contents. The kernel release includes the version to distinguish
matching modules and headers.

Results in `dist/<version>/`:

- `uconsole-kernel-cm4_<version>_arm64.deb`
- `uconsole-kernel-headers-cm4_<version>_arm64.deb`
- `kernel.config` and `kernel-commit`

The headers package depends on the exact matching kernel package version.
Packaging checks required drivers, DTBs, overlays, generated headers and the
headers build link before creating the final packages.

## Kernel source

The first build clones Raspberry Pi Linux and selects `KERNEL_REF` (default
`rpi-6.12.y`). Later builds reuse that checkout without fetching updates.
To update it or select another branch, tag or commit:

```console
make update KERNEL_REF=rpi-6.12.y
make cm4 KERNEL_REF=rpi-6.12.y
```

To build an existing checkout at its current commit:

```console
make cm4 KERNEL_DIR=/absolute/path/to/linux
```

This writes build files into that checkout. `make update` requires clean tracked
source files. `make clean` removes this project's `build/` and `dist/`; it does
not clean an external checkout.

## Install on the uConsole

Copy the two packages from one release directory, then install both together:

```console
sudo apt install ./uconsole-kernel-cm4_<version>_arm64.deb ./uconsole-kernel-headers-cm4_<version>_arm64.deb
```

Packages use versioned `/boot/vmlinuz-<release>`, `/lib/modules/<release>/`,
and `/lib/modules/<release>/dtb/` paths. Headers include the matching external
module build files and `/lib/modules/<release>/build` link.

**Boot activation and rollback are deferred.** The image retains upstream
kernel package hooks, which invoke the installed system's kernel/initramfs
hooks. Their Raspberry Pi boot-partition behavior has not been verified.
The package does not edit `config.txt`; an example is installed in
`/usr/share/doc/uconsole-kernel-cm4/config.txt.example`.
A successful package install is not yet a verified bootable deployment.

No apt repository is required to install these files. Repository publishing
is outside this build workflow.
