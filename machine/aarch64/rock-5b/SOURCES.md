# ROCK 5B sources and hardware contract

The `buildroot` target uses upstream Buildroot `2026.05`, pinned to
commit `313414b92c2501a2bc123ffa1b6383dca464de05`. Its
[`rock5b_defconfig`](https://github.com/buildroot/buildroot/blob/313414b92c2501a2bc123ffa1b6383dca464de05/configs/rock5b_defconfig)
selects Linux `6.12.4` and U-Boot `2025.01`. The hashes supplied under
`board/radxa/rock5b/patches` verify both source archives.

The recipe inherits the shared Buildroot builder and its base image:
`registry.gitlab.com/buildroot.org/buildroot/base:20250218.2110`.
Buildroot builds the cross compiler, kernel, firmware, BusyBox and CPIO
root filesystem through its normal package dependencies.

`buildroot-external/configs/rock5b_qemu.config` adds a serial-console CPIO
root filesystem and the board hooks. Linux retains the upstream ARM64
defconfig and ROCK 5B fragment. The additional kernel fragment enables
kernel configuration export and built-in MTD/SFC drivers. The kernel
patch adds the XTX XT25F128 JEDEC geometry.

The Linux DTB is compiled from upstream `rk3588-rock-5b.dts` with symbol
support. `board/linux.dtso` disables the unmodeled power controller and
CPU sleep state. The upstream SCMI SMC transport and shared-memory
description are retained.

U-Boot retains `rock5b-rk3588_defconfig`, the upstream Buildroot fragment,
and its native SPL and binman build. `board/uboot.config` selects an
in-memory environment and the SPI Linux boot command. The included
`board/rock5b-qemu.dtsi` makes U-Boot the native FIT's firmware target,
so SPL transfers control to U-Boot proper in EL2. TF-A and RKBIN remain
upstream board build dependencies; QEMU provides PSCI and SCMI services.

Buildroot exports `spl/u-boot-spl.bin` as `u-boot-spl.bin`, as well as
the native `u-boot.itb` and `u-boot-rockchip-spi.bin`. QEMU loads SPL at
`0x00000000` and supplies the FSPI boot-source indication. SPL reads the
U-Boot FIT at the upstream SPI offset `0x60000`, verifies its hashes,
loads U-Boot at `0x00a00000`, and appends its upstream control DTB.
BootROM, DDR training firmware and BL31 are outside the execution path.

The kernel image-install hook exports configuration and release metadata.
The post-fakeroot hook archives loadable modules separately and removes
them from the CPIO staging directory, preserving the installed target
tree for subsequent builds. It regenerates module indexes while retaining
built-in module metadata. The post-image hook applies the Linux DT
overlay, compresses the kernel with LZMA, and builds the Linux FIT using
Buildroot's host image tools.

The flash image preserves the native Rockchip SPI firmware image and puts
the Linux FIT at `0x400000`. Bounds checks protect the 4 MiB firmware and
12 MiB Linux regions. The shared packaging script publishes the required
files in one release archive with its checksum.

The UART2 console is at `0xfeb50000`, and SFC is at `0xfe2b0000`.
RAM starts at zero, ends at `0xf0000000`, and continues at `0x100000000`
when more memory is configured. Firmware discovers RAM through the PMU
GRF OS registers. The Linux FIT buffer is at `0x10000000`, the kernel
at `0x02000000`, the FDT at `0x12000000`, and the initramfs at `0x12180000`.
U-Boot may relocate the FDT and initramfs within its available RAM.

Direct Linux boot uses the same kernel, adapted board DTB and initramfs.
