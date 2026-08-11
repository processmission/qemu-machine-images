#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=scripts/machine-image.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../scripts/machine-image.sh"

machine_image_launcher_init "${BASH_SOURCE[0]}" "$@"

# Validate only the release images consumed by the selected boot mode
case "${MACHINE_IMAGE_BOOT_MODE}" in
    firmware) required_images=("${FIRMWARE_IMAGES[@]}") ;;
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
    firmware)
        # QEMU does not model the Boot ROM or SPL loading sequence
        boot_arguments=(
            -device \
            "loader,file=${MACHINE_IMAGE_DIR}/u-boot.bin,addr=0x87800000,cpu-num=0"
        )
        ;;
    linux)
        boot_arguments=(
            -kernel "${MACHINE_IMAGE_DIR}/zImage"
            -dtb "${MACHINE_IMAGE_DIR}/imx6ul-14x14-evk.dtb"
            -append \
            "console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw"
        )
        ;;
esac

# USDHC2 is mmc1 in U-Boot and mmcblk1 in Linux
machine_image_exec "${QEMU_EXECUTABLE}" \
    -machine "${QEMU_MACHINE}" \
    -m 512M \
    -display none \
    -monitor none \
    -serial stdio \
    "${boot_arguments[@]}" \
    -drive "file=${MACHINE_IMAGE_DIR}/sdcard.img,if=sd,index=1,format=raw" \
    "${MACHINE_IMAGE_QEMU_ARGUMENTS[@]}"
