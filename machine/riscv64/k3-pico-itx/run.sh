#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=scripts/machine-image.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../scripts/machine-image.sh"

machine_image_launcher_init "${BASH_SOURCE[0]}" "$@"

machine_image_prepare \
    "${MACHINE_IMAGE_REPO_ROOT}" \
    "${ARCHITECTURE}" \
    "${QEMU_MACHINE}" \
    "${RELEASE_ASSET_PREFIX}" \
    "${REQUIRED_IMAGES[@]}"

machine_image_exec "${QEMU_EXECUTABLE}" \
    -machine "${QEMU_MACHINE}" \
    -display none \
    -monitor none \
    -serial stdio \
    -bios "${MACHINE_IMAGE_DIR}/fw_dynamic.bin" \
    -kernel "${MACHINE_IMAGE_DIR}/u-boot.bin" \
    -dtb "${MACHINE_IMAGE_DIR}/k3-pico-itx-qemu-uboot.dtb" \
    -drive \
    "file=${MACHINE_IMAGE_DIR}/k3-qemu-sd.raw,if=sd,format=raw,snapshot=on" \
    -no-reboot \
    "${MACHINE_IMAGE_QEMU_ARGUMENTS[@]}"
