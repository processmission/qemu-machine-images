#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=scripts/machine-image.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../scripts/machine-image.sh"

machine_image_launcher_init "${BASH_SOURCE[0]}" "$@"

# Validate only the release images consumed by the selected boot mode
case "${MACHINE_IMAGE_BOOT_MODE}" in
    uboot) required_images=("${UBOOT_IMAGES[@]}") ;;
    linux) required_images=("${LINUX_IMAGES[@]}") ;;
    *) machine_image_die "unimplemented boot mode: ${MACHINE_IMAGE_BOOT_MODE}" ;;
esac

machine_image_prepare \
    "${MACHINE_IMAGE_REPO_ROOT}" \
    "${ARCHITECTURE}" \
    "${QEMU_MACHINE}" \
    "${RELEASE_ASSET_PREFIX}" \
    "${required_images[@]}"

case "${MACHINE_IMAGE_BOOT_MODE}" in
    uboot)
        # SPL loads U-Boot from the same SPI NOR image as the Linux FIT.
        boot_arguments=(
            -bios "${MACHINE_IMAGE_DIR}/u-boot-spl.bin"
            -drive "if=mtd,index=0,file=${MACHINE_IMAGE_DIR}/spi-nor.img,format=raw,snapshot=on"
        )
        ;;
    linux)
        # Direct Linux boot bypasses U-Boot and leaves the SPI NOR erased
        boot_arguments=(
            -kernel "${MACHINE_IMAGE_DIR}/Image"
            -dtb "${MACHINE_IMAGE_DIR}/rk3588-rock-5b.dtb"
            -initrd "${MACHINE_IMAGE_DIR}/rootfs.cpio.gz"
            -append "${QEMU_LINUX_APPEND:-console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfeb50000 rdinit=/init}"
        )
        ;;
esac

machine_image_exec "${QEMU_EXECUTABLE}" \
    -machine "${QEMU_MACHINE}" \
    -smp 8 \
    -m 2G \
    -display none \
    -monitor none \
    -serial stdio \
    "${boot_arguments[@]}" \
    "${MACHINE_IMAGE_QEMU_ARGUMENTS[@]}"
