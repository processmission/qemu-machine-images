# Source provenance

All source inputs are pinned by commit or content hash. Branch names are not
used as reproducibility locks.

## K3 SDK v1.0.2

| Component | Repository | Commit |
| --- | --- | --- |
| Linux | `spacemit-com/linux-6.18` | `0ffac20d9ef93c572b649037213bbe20ef59a714` |
| OpenSBI | `spacemit-com/opensbi` | `e5fc30394ac18263fa045dcaef52f86f180ed512` |
| U-Boot | `spacemit-com/uboot-2022.10` | `6747f87ae4cd359ff6e22daa38b06c3ecc2fecb4` |
| Buildroot | `spacemit-com/buildroot` | `06a303b332a7216c6ca9360dd7c7f52a3fb8b1da` |
| Buildroot ext | `spacemit-com/buildroot-ext` | `e4f708f2be0aacba300a0e5042856592378902d4` |
| SDK scripts | `spacemit-com/scripts` | `96418825a37a1cf07d3275c13d9d3329934224f0` |
| Manifest | `spacemit-com/manifests` | `6d767b42fdbd759dc9511b8a13523c3de42aaa5a` |

The table records the commits peeled from the SDK's annotated v1.0.2 tags.
Linux, OpenSBI, U-Boot, and Buildroot are compiled for the release. The same
Linux and initramfs artifacts are used by the direct and U-Boot boot paths.

OpenSBI is built as `PLATFORM=generic` with
`configs/opensbi-qemu_defconfig`. The SDK's K3 defconfig emits X100-private
cache/PMA CSR instructions before platform matching, while QEMU's Linux-first
machine intentionally models the standard architectural subset. A small patch
guards vendor-only cache helpers and mode-switch CSR writes which otherwise
break or hang the generic build. The patch is stored under
`patches/opensbi/` and is applied after the pinned source commit is verified.
Its SHA-256 is
`dc58a7e4e657cb477ca3025c5fed22d96cbb87dc1941ba3147ea00a7d57072ce`.

U-Boot is built from `k3_defconfig` as `u-boot.bin`, with `CONFIG_SYSCON=y`
and `CONFIG_RESET_SYSCON=y` enabled for the QEMU device tree. The patch is
stored under `patches/uboot/`:

- The K3 SDHCI driver normally asks its input clock provider to change rate.
  QEMU describes the 52 MHz input with fixed clocks, whose `set_rate`
  operation returns `-ENOSYS`, so the patch accepts that result while
  retaining all other clock errors. Its SHA-256 is
  `3c5defc321fe4f8c94e653f2bf231869be70aeeb5c9788094df5d7cf7a924f27`.

## SD image layout

`k3-qemu-sd.raw` is a 128 MiB raw disk with a deterministic GPT:

| Item | Value |
| --- | --- |
| Disk GUID | `4b335344-0000-4000-8000-000000000001` |
| Partition | `bootfs`, sectors 2048 through 260095 |
| Partition GUID | `4b335344-0001-4000-8000-000000000001` |
| File system | FAT32, label `K3BOOT`, volume ID `4b335144` |

The boot partition contains `Image`, `k3-pico-itx-qemu-linux-sd.dtb`,
`k3-qemu-initramfs.cpio.gz`, and `env_k3.txt`. GPT identifiers, FAT metadata,
file ordering, timestamps, and XZ settings are fixed by the build recipe. The
QEMU command uses `snapshot=on`, so a functional-test run never modifies the
published image.

## Toolchain and container

- Toolchain: `spacemit-toolchain-linux-glibc-x86_64-v1.2.2.tar.xz`
- URL: `https://archive.spacemit.com/toolchain/spacemit-toolchain-linux-glibc-x86_64-v1.2.2.tar.xz`
- SHA-256: `a4bb97aba723ea642db9261d517cd98660404a4e42a37b2c3b86a3adc4ee78e9`
- Compiler: GCC 15.2.0, prefix `riscv64-unknown-linux-gnu-`
- Container base: Ubuntu 24.04 amd64 digest
  `sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`

The Linux build uses a fixed timestamp derived from the pinned Linux commit:
`SOURCE_DATE_EPOCH=1779807738`, `KBUILD_BUILD_USER=spacemit`, and
`KBUILD_BUILD_HOST=k3-sdk-v1.0.2`. It starts from `k3_defconfig` and clears
`CONFIG_INITRAMFS_SOURCE`; the SDK's bundled hardware rootfs is not part of
the QEMU `Image`, because the release supplies a functional-test initramfs
alongside the other machine images. OpenSBI, U-Boot, and the vendor Buildroot
snapshot are built serially so their output does not depend on make scheduling.

## Release archive used as an oracle

The official prebuilt SDK release was used only to validate the expected boot
contract before compiling the pinned sources:

- URL: `https://archive.spacemit.com/image/k3/version/buildroot/v1.0.2/Buildroot-K3-v1.0.2-20260530144408.zip`
- Size: `381023434` bytes
- SHA-256: `681f2fe0582a907e3a743dc791016215c5d5bb2a1d0c6ada0c52df24274c0`
- Vendor MD5: `ac768dfd4a7a0831bd68e001ab169030`

No binary from that archive is published as a release artifact here.
