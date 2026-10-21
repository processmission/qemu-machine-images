#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=scripts/machine-image.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../scripts/machine-image.sh"

machine_image_launcher_init "${BASH_SOURCE[0]}" "$@"

case "${MACHINE_IMAGE_BOOT_MODE}" in
    direct) boot_images=(Image rootfs.cpio.gz k230-qemu.dtb) ;;
    firmware) boot_images=(u-boot boot.itb) ;;
esac

machine_image_prepare \
    "${MACHINE_IMAGE_REPO_ROOT}" "${ARCHITECTURE}" "${QEMU_MACHINE}" \
    "${RELEASE_ASSET_PREFIX}" "${boot_images[@]}"

bootargs='console=ttyS0,115200 earlycon=uart8250,mmio32,0x91400000 cma=0'
qemu_args=(-machine "${QEMU_MACHINE}" -nographic -no-reboot)

case "${MACHINE_IMAGE_BOOT_MODE}" in
    direct)
        qemu_args+=(
            -bios default
            -kernel "${MACHINE_IMAGE_DIR}/Image"
            -dtb "${MACHINE_IMAGE_DIR}/k230-qemu.dtb"
            -initrd "${MACHINE_IMAGE_DIR}/rootfs.cpio.gz"
            -append "${bootargs}"
        )
        ;;
    firmware)
        qemu_args+=(
            -bios "${MACHINE_IMAGE_DIR}/u-boot"
            -device "loader,file=${MACHINE_IMAGE_DIR}/boot.itb,addr=0xc100000,force-raw=on"
        )
        ;;
esac

machine_image_exec "${QEMU_EXECUTABLE}" \
    "${qemu_args[@]}" "${MACHINE_IMAGE_QEMU_ARGUMENTS[@]}"
