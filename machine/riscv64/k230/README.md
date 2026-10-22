# K230 images

This machine uses the official K230 Linux SDK's Buildroot build to produce
Linux, a BusyBox initramfs, U-Boot, OpenSBI, and a QEMU device tree. Source
revisions and the QEMU adaptations are described in [SOURCES.md](SOURCES.md).

The Xuantie toolchain needs a native Linux amd64 builder. Select one with
`--builder NAME` when building from a different host architecture.

## Build

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

For local builds without GitHub Actions cache credentials, add
`--set '*.cache-from=' --set '*.cache-to='` to the Bake command.

The SDK prepares its Buildroot 2025.02.1 tree with its own `make sync`
target. The shared configuration helper registers `buildroot-external/`,
then Buildroot builds all components from the configured output directory.
The container exports `images/`; shared packaging selects the six files
listed in `machine.conf`.

## Run

Use a QEMU binary that implements `-machine k230`:

```sh
QEMU_EXECUTABLE=/absolute/path/to/qemu-system-riscv64 \
  machine/riscv64/k230/run.sh
```

Direct boot uses QEMU's bundled OpenSBI, the Linux `Image`, the QEMU DTB,
and the external initramfs. The command line enables UART0 at 115200 baud.

To boot through the SDK's U-Boot and OpenSBI:

```sh
QEMU_EXECUTABLE=/absolute/path/to/qemu-system-riscv64 \
  machine/riscv64/k230/run.sh firmware
```

QEMU places `boot.itb` in RAM at `0x0c100000`. U-Boot automatically loads
OpenSBI, Linux, the device tree, and the initramfs from this FIT image,
then starts OpenSBI and Linux. It verifies the FIT payload hashes and
writes the initramfs addresses into the device tree. The load addresses are:

| Image | Address |
| --- | --- |
| OpenSBI | `0x08000000` |
| Linux | `0x08200000` |
| Device tree | `0x0a000000` |
| Initramfs | `0x10000000` |

The archive also includes `fw_jump.uImage` for firmware flows that load
the Linux components separately. The QEMU K230 machine needs SDHCI support
before it can load these images from an SD card.

Log in as `root` with an empty password at `k230 login:`. Exit QEMU with
`Ctrl+A X`. To use a locally packaged archive, set
`QEMU_MACHINE_IMAGES_RELEASE_BASE_URL="file://$(pwd)/dist"` when launching.

The QEMU profile exposes one hart, 2 GiB RAM, CLINT, PLIC, and UART0.
It uses a 10 MHz timebase to match the emulated timer. Linux and userspace
use the scalar RV64GC instruction set supported by QEMU's K230 little core.
The profile excludes the SDK's camera, display, AI, and Wi-Fi applications
and exports no physical-board disk images.
