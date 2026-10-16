#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=scripts/machine-image.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../scripts/machine-image.sh"

machine_image_launcher_init "${BASH_SOURCE[0]}" "$@"

case "${MACHINE_IMAGE_BOOT_MODE}" in
    direct)
        boot_images=(Image rootfs.cpio.gz k230-canmv.dtb)
        ;;
    firmware)
        # machine_image_launcher_init loads this array from machine.conf.
        # shellcheck disable=SC2153
        boot_images=("${REQUIRED_IMAGES[@]}")
        ;;
esac

machine_image_prepare \
    "${MACHINE_IMAGE_REPO_ROOT}" \
    "${ARCHITECTURE}" \
    "${QEMU_MACHINE}" \
    "${RELEASE_ASSET_PREFIX}" \
    "${boot_images[@]}"

qemu_args=(-machine "${QEMU_MACHINE}" -nographic -no-reboot)

case "${MACHINE_IMAGE_BOOT_MODE}" in
    direct)
        qemu_args+=(
            -bios default
            -kernel "${MACHINE_IMAGE_DIR}/Image"
            -dtb "${MACHINE_IMAGE_DIR}/k230-canmv.dtb"
            -initrd "${MACHINE_IMAGE_DIR}/rootfs.cpio.gz"
            -append "console=ttyS0,115200 earlycon=sbi"
        )
        ;;
    firmware)
        initrd_size="$(wc -c < "${MACHINE_IMAGE_DIR}/rootfs.cpio.gz")"
        (( initrd_size > 0 && initrd_size < 0x10000000 )) || \
            machine_image_die "initramfs must fit between 0x10000000 and 0x20000000"
        printf -v initrd_end '0x%x' "$((0x10000000 + initrd_size))"
        printf '%s\n' \
            'Press Enter to stop U-Boot autoboot, then run:' \
            'setenv bootargs console=ttyS0,115200 earlycon=sbi' \
            'fdt addr 0xa000000' \
            'fdt resize 8192' \
            'fdt set /chosen linux,initrd-start <0x0 0x10000000>' \
            "fdt set /chosen linux,initrd-end <0x0 ${initrd_end}>" \
            'bootm 0xc100000 - 0xa000000' >&2
        qemu_args+=(
            -bios "${MACHINE_IMAGE_DIR}/u-boot"
            -device "loader,file=${MACHINE_IMAGE_DIR}/fw_jump.uImage,addr=0xc100000,force-raw=on"
            -device "loader,file=${MACHINE_IMAGE_DIR}/Image,addr=0x8200000,force-raw=on"
            -device "loader,file=${MACHINE_IMAGE_DIR}/rootfs.cpio.gz,addr=0x10000000,force-raw=on"
            -device "loader,file=${MACHINE_IMAGE_DIR}/k230-canmv.dtb,addr=0xa000000,force-raw=on"
        )
        ;;
esac

machine_image_exec "${QEMU_EXECUTABLE}" \
    "${qemu_args[@]}" "${MACHINE_IMAGE_QEMU_ARGUMENTS[@]}"
