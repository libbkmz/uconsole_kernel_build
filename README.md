# v3

Minimal CM4/CM5 uConsole kernel builder for Debian or Ubuntu on x86_64 and
AArch64. It shallow-clones Raspberry Pi Linux when absent, reuses it on later
builds, and builds the drivers, DTBs, overlays, and mandatory kernel
configuration stored in this directory.

```console
make deps
make cm5 # or: make cm4
```

Set `KERNEL_BRANCH` at the top of `Makefile` or override it when building:

```console
make KERNEL_BRANCH=rpi-6.12.y cm5
```

Optional kernel config profiles can be layered over `configs/base.conf`:

```console
make PROFILES="debug development" cm5
```

The result is in `dist/`. Each archive contains one timestamped directory with
`boot/firmware/` and `lib/` inside it, so normal extraction cannot overwrite the
running system. It includes the kernel, platform DTBs, Raspberry Pi overlays,
uConsole overlay and drivers, module tree, kernel config, System.map, and
`config.txt.additions`:

```console
tar xzf dist/uconsole-cm5-*.tar.gz
```

Inspect that directory, then deploy it with `rsync` when ready. Don't use
`--strip-components` or extract the archive directly over `/`.

After deploying, review and append `boot/firmware/config.txt.additions` to the
device's existing `/boot/firmware/config.txt`. The build never edits the
device's boot configuration.
