# K230 Linux SDK images

This machine builds Linux, a Buildroot initramfs, OpenSBI, U-Boot, and a QEMU
device tree through the official Kendryte Linux SDK's Buildroot workflow.
Pinned sources are listed in [SOURCES.md](SOURCES.md).
The initramfs provides BusyBox, glibc, initialization scripts, and a serial
login. The build starts with the SDK's `k230_canmv_defconfig` and merges
`recipe/configs/buildroot.config` for QEMU's serial-console initramfs.
The SDK's Xuantie toolchain requires a native Linux amd64 Buildx builder.
Select the builder with `--builder NAME` when building from another host.

## Build and package

From the repository root:

```sh
docker buildx bake \
  --file scripts/docker-bake.hcl \
  --file machine/riscv64/k230/build.hcl \
  release-components
scripts/assemble-machine-images.sh components output
scripts/finalize-machine-images.sh machine/riscv64/k230 output/images
scripts/package-machine-images.sh \
  machine/riscv64/k230/machine.conf output dist "v$(cat VERSION)"
```

For a local builder without GitHub Actions cache credentials, add
`--set '*.cache-from=' --set '*.cache-to='` to the Bake command.

The archive contains `Image`, `rootfs.cpio.gz`, `k230-canmv.dtb`, `u-boot`,
and `fw_jump.uImage` under `images/`.

## Run

Use a QEMU binary that supports `-machine k230`:

```sh
QEMU_EXECUTABLE="$HOME/qemu/build/qemu-system-riscv64" \
  machine/riscv64/k230/run.sh direct
```

Direct boot is the default. It uses QEMU's bundled OpenSBI firmware and the
SDK Linux kernel with `console=ttyS0,115200 earlycon=sbi`.

To start through SDK U-Boot:

```sh
QEMU_EXECUTABLE="$HOME/qemu/build/qemu-system-riscv64" \
  machine/riscv64/k230/run.sh firmware
```

The launcher prints the U-Boot commands with the initramfs end address
calculated from the downloaded file. Press Enter to stop autoboot, then enter
those commands at `K230#`. The initramfs is loaded at `0x10000000`; Linux,
the device tree, and the OpenSBI uImage are loaded at `0x08200000`,
`0x0a000000`, and `0x0c100000` respectively.

Log in as `root` with an empty password at `canaan login:`. Exit QEMU with
`Ctrl+A X`.

To use locally packaged images, set
`QEMU_MACHINE_IMAGES_RELEASE_BASE_URL="file://$(pwd)/dist"` when launching.
