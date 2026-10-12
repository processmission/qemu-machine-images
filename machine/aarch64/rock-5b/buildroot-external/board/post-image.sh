#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
# SPDX-License-Identifier: MIT

set -euo pipefail

board_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${HOST_DIR}/bin:${PATH}"
temporary="$(mktemp -d "${BUILD_DIR}/rock5b-images.XXXXXX")"
trap 'rm -rf -- "${temporary}"' EXIT
export TMPDIR="${temporary}"
cd "${BINARIES_DIR}"

dtc -@ -I dts -O dtb -o "${temporary}/linux.dtbo" "${board_dir}/linux.dtso"
fdtoverlay -i rk3588-rock-5b.dtb -o "${temporary}/linux.dtb" \
    "${temporary}/linux.dtbo"
install -m 0644 "${temporary}/linux.dtb" rk3588-rock-5b.dtb

kernel_size="$(wc -c < Image)"
firmware_size="$(wc -c < u-boot-rockchip-spi.bin)"
(( kernel_size > 0 && kernel_size <= 0x4000000 ))
(( firmware_size > 0 && firmware_size <= 0x400000 ))
xz --format=lzma -9 -c Image > Image.lzma
mkimage -E -B 0x200 -D '-I dts -O dtb -p 0x1000 -i .' \
    -f "${board_dir}/boot.its" boot.itb
fit_size="$(wc -c < boot.itb)"
(( fit_size <= 0xc00000 )) || {
    echo 'Linux FIT exceeds the 12 MiB flash payload region' >&2
    exit 1
}

dd if=/dev/zero bs=1048576 count=16 status=none | \
    LC_ALL=C tr '\000' '\377' > spi-nor.img
dd if=u-boot-rockchip-spi.bin of=spi-nor.img conv=notrunc status=none
dd if=boot.itb of=spi-nor.img bs=1048576 seek=4 conv=notrunc status=none
