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
`caec6f00ab5b95dd020088aaf7dec7e4b77d44aaa97c33297e23c89a1b6b9dc0`.

U-Boot is built from `k3_defconfig` as `u-boot.bin`, with `CONFIG_SYSCON=y`
and `CONFIG_RESET_SYSCON=y` enabled for the QEMU device tree. Two patches are
stored under `patches/uboot/`:

- The K3 SDHCI driver normally asks its input clock provider to change rate.
  QEMU describes the 52 MHz input with fixed clocks, whose `set_rate`
  operation returns `-ENOSYS`, so the first patch accepts that result while
  retaining all other clock errors. Its SHA-256 is
  `3c5defc321fe4f8c94e653f2bf231869be70aeeb5c9788094df5d7cf7a924f27`.
- The generic SDHCI command loop used by this vendor release checks its timer
  before accepting completion bits returned by the final status read. The
  second patch only reports a timeout while required completion bits are
  still absent. Its SHA-256 is
  `8064e93e18621f956bf0f3f81c5562611500bca93ccc237ca1278c298a4160a3`.

## SD image layout

`k3-qemu-sd.raw.xz` expands to a 128 MiB raw disk with a deterministic GPT:

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
the QEMU `Image`, because the release supplies a separate functional-test
initramfs. OpenSBI, U-Boot, and the vendor Buildroot snapshot are built
serially so their output does not depend on make scheduling.

## Release archive used as an oracle

The official prebuilt SDK release was used only to validate the expected boot
contract before compiling the pinned sources:

- URL: `https://archive.spacemit.com/image/k3/version/buildroot/v1.0.2/Buildroot-K3-v1.0.2-20260530144408.zip`
- Size: `381023434` bytes
- SHA-256: `681f2fe0582a907e3a743dc791016215c5d5bb2a1d0c6ada0c52df24274c0`
- Vendor MD5: `ac768dfd4a7a0831bd68e001ab169030`

No binary from that archive is published as a release artifact here.

## eweOS functional initramfs

The eweOS functional-test initramfs is imported from the immutable
`eweos-20260425-k3-qemu2` Release in
`zevorn/spacemit-k3-qemu-images`. The build verifies SHA-256
`911c88733ca5c8c76311033cc051f1672b94861ef8a525368f5cd9d4b64fc943`
before exporting the file. The imported archive is 50,134,389 bytes.

Its official eweOS root filesystem is pinned to RISC-V OCI manifest digest
`sha256:10120b0526e03eb2ffde88dd640744eda1a1b6c45be60b41ea60a0f846014363`.
The image adds `fastfetch` 2.66.0-1 and `yyjson` 0.12.0-2 from the official
eweOS repository; their package SHA-256 values are
`8a2a9dd98a8183d3cff9e66c767dd3a80e3c83fdb2aa4e50e61e74964d454334`
and
`508f6c5dea7ea3dc96bc5d4f69824685c2c1387bb937d1904483f3dc397c8044`.

Importing the verified historical archive preserves the exact userspace
already exercised by QEMU. The originating repository did not contain a
complete reconstruction recipe for that OCI-derived archive, so this
repository does not claim to rebuild it from source.
