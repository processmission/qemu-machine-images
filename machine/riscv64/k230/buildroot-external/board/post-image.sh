#!/bin/sh
# SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
# SPDX-License-Identifier: MIT

set -eu

board_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
export PATH="${HOST_DIR}/bin:${PATH}"
cd "${BINARIES_DIR}"

firmware_size="$(wc -c < fw_jump.bin)"
kernel_size="$(wc -c < Image)"
initrd_size="$(wc -c < rootfs.cpio.gz)"
[ "${firmware_size}" -gt 0 ] && [ "${firmware_size}" -le "$((0x200000))" ]
[ "${kernel_size}" -gt 0 ] && [ "${kernel_size}" -le "$((0x1e00000))" ]
[ "${initrd_size}" -gt 0 ] && [ "${initrd_size}" -lt "$((0x10000000))" ]

mkimage \
    -A riscv -O linux -T kernel -C none \
    -a 0x08000000 -e 0x08000000 -n opensbi \
    -d fw_jump.bin fw_jump.uImage
mkimage -D '-I dts -O dtb -p 0x1000 -i .' \
    -f "${board_dir}/boot.its" boot.itb
fit_size="$(wc -c < boot.itb)"
[ "${fit_size}" -le "$((0x3f00000))" ] || {
    echo 'K230 FIT overlaps the initramfs load address' >&2
    exit 1
}
