#!/bin/sh

set -eu

images="$1"
install -m 0644 "${images}/k230-canmv-qemu.dtb" "${images}/k230-canmv.dtb"
mkimage -A riscv -O linux -T kernel -C none \
    -a 0x08000000 -e 0x08000000 -n OpenSBI \
    -d "${images}/fw_jump.bin" "${images}/fw_jump.uImage"
