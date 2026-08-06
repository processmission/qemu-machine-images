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
    -machine "${QEMU_MACHINE},msel=11" \
    -smp 5 \
    -m 8G \
    -display none \
    -monitor none \
    -serial stdio \
    -bios "${MACHINE_IMAGE_DIR}/u-boot-spl.bin" \
    -drive "file=${MACHINE_IMAGE_DIR}/sdcard.img,if=sd,format=raw" \
    "${MACHINE_IMAGE_QEMU_ARGUMENTS[@]}"
