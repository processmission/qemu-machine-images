#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )); then
    echo "usage: $0 IMAGES_DIR" >&2
    exit 2
fi

readonly IMAGES_ROOT="$(realpath -e -- "$1")"
[[ -d "${IMAGES_ROOT}" ]] || {
    echo "images directory does not exist: $1" >&2
    exit 1
}

readonly SDCARD_IMAGE="${IMAGES_ROOT}/sdcard.img"
[[ ! -L "${SDCARD_IMAGE}" && -f "${SDCARD_IMAGE}" ]] || {
    echo "SD card image is not a regular file: ${SDCARD_IMAGE}" >&2
    exit 1
}

readonly TARGET_SIZE=$((4 * 1024 * 1024 * 1024))
readonly ORIGINAL_SIZE="$(stat --format='%s' -- "${SDCARD_IMAGE}")"
if (( ORIGINAL_SIZE > TARGET_SIZE )); then
    echo \
        "SD card image exceeds the 4 GiB target: ${ORIGINAL_SIZE} bytes" \
        >&2
    exit 1
fi

readonly TEMPORARY_DIR="$(
    mktemp --directory --tmpdir="${IMAGES_ROOT}" .sdcard-finalize.XXXXXX
)"
readonly TEMPORARY_IMAGE="${TEMPORARY_DIR}/sdcard.img"

cleanup() {
    rm -f -- "${TEMPORARY_IMAGE}"
    rmdir -- "${TEMPORARY_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

cp --reflink=auto --sparse=always -- \
    "${SDCARD_IMAGE}" "${TEMPORARY_IMAGE}"
truncate --size="${TARGET_SIZE}" -- "${TEMPORARY_IMAGE}"
sgdisk -e "${TEMPORARY_IMAGE}"
sgdisk -v "${TEMPORARY_IMAGE}"

readonly FINAL_SIZE="$(stat --format='%s' -- "${TEMPORARY_IMAGE}")"
if (( FINAL_SIZE != TARGET_SIZE )); then
    echo "final SD card image has an unexpected size: ${FINAL_SIZE} bytes" >&2
    exit 1
fi

mv --force -- "${TEMPORARY_IMAGE}" "${SDCARD_IMAGE}"
rmdir -- "${TEMPORARY_DIR}"
trap - EXIT

printf 'finalized %s as a 4 GiB GPT disk image\n' "${SDCARD_IMAGE}"
