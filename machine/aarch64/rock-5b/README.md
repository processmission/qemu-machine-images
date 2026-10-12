# ROCK 5B SPL, U-Boot and Linux images

The `uboot` mode starts U-Boot SPL through QEMU's `-bios` option. SPL
loads U-Boot proper from the RK3588 SPI flash controller. U-Boot then
loads a Linux FIT from the same 16 MiB XT25F128 SPI NOR and starts the
Buildroot initramfs. The `linux` mode uses QEMU's direct kernel loader.

The shared Buildroot builder uses upstream `rock5b_defconfig` from
Buildroot `2026.05`, with `buildroot-external/` providing the QEMU
configuration and image hooks. It builds Linux `6.12.4`, U-Boot
`2025.01`, SPL, and the BusyBox/glibc root filesystem. Device trees are
built from the upstream board sources.

The release archive contains `u-boot-spl.bin` and `spi-nor.img` for
firmware boot, plus `Image`, `rk3588-rock-5b.dtb` and `rootfs.cpio.gz`
for direct Linux boot. It also includes `kernel.config`,
`kernel-revision.txt`, `kernel-release.txt` and `kernel-modules.tar.xz`.
Loadable modules are preserved in the separate archive. The initramfs
retains built-in module metadata, and UART and SFC drivers are built in.

## Build and package

Run from the repository root with Docker Buildx, GNU coreutils, GNU tar,
and `zstd` available. Buildroot cross-compiles the ARM64 images on a Linux
amd64 worker. Device-tree compilation, kernel compression, FIT generation
and SPI NOR assembly run inside the build container.

```sh
export TMPDIR="$PWD/.cache/rock-5b/temporary"
mkdir -p "$TMPDIR"
OUTPUT_DIR=.cache/rock-5b/components docker buildx bake \
  --file scripts/docker-bake.hcl \
  --file machine/aarch64/rock-5b/build.hcl \
  --set '*.cache-from=' --set '*.cache-to=' release-components
scripts/assemble-machine-images.sh .cache/rock-5b/components .cache/rock-5b/output
scripts/finalize-machine-images.sh machine/aarch64/rock-5b .cache/rock-5b/output/images
scripts/package-machine-images.sh \
  machine/aarch64/rock-5b/machine.conf .cache/rock-5b/output dist "v$(cat VERSION)"
```

The assembly output directory must be empty. Use `--builder NAME` to select
a Buildx worker. On macOS, put the GNU tools' `gnubin` directories on
`PATH` before packaging or launching images. Add `.cache/rock-5b/` to the
local Git exclude file when using it for build outputs.

The assembly directory also retains the native `u-boot.itb`,
`u-boot-rockchip-spi.bin`, `Image.lzma` and Linux `boot.itb` used to
construct the flash image. See [SOURCES.md](SOURCES.md) for the source
revisions and hardware contract.

## Run

Use a QEMU `rock-5b` implementation with SPL firmware boot, SBUSCRU SPLL
registers and SCMI over SMC. For a package in the local `dist` directory:

```sh
QEMU_EXECUTABLE=/absolute/path/to/qemu-system-aarch64 \
QEMU_MACHINE_IMAGES_RELEASE_BASE_URL="file://$(pwd)/dist" \
  machine/aarch64/rock-5b/run.sh uboot
```

Replace `uboot` with `linux` for direct Linux boot. The `linux` mode passes
`Image`, `rk3588-rock-5b.dtb` and `rootfs.cpio.gz` to QEMU and sets the
kernel command line from `QEMU_LINUX_APPEND`; the default selects the
`ttyS2` console at 1500000 baud and `rdinit=/init`.

The launcher configures eight CPUs and 2 GiB RAM; the `uboot` mode
attaches a flash snapshot. Firmware RAM discovery follows the RK3588
PMU GRF memory description, while direct Linux boot uses QEMU's RAM
configuration. Log in as `root` with an empty password at `rock5b login:`.
The Linux model string is `Radxa ROCK 5B`. Changes inside the initramfs
last until reboot.

To select a package whose version differs from `VERSION`, set
`QEMU_MACHINE_IMAGES_VERSION` to that version without its leading `v`.

## Flash layout

| Offset | Length | Contents |
|---|---|---|
| `0x000000` | `0x60000` | Native Rockchip loader image |
| `0x060000` | `0x3a0000` | U-Boot FIT and erased padding |
| `0x400000` | `0xc00000` | Linux FIT region |

The native U-Boot FIT selects U-Boot proper as the firmware executed by
SPL. The Linux FIT contains an ARM64 LZMA-compressed kernel, gzip
initramfs and Linux device tree, protected by SHA-256 hashes. U-Boot
reads it with `sf read` and invokes `bootm`. The load addresses require
at least 512 MiB RAM. QEMU attaches the flash as `if=mtd,index=0`;
the upstream U-Boot configuration uses SPI bus 5 and chip select 0.
