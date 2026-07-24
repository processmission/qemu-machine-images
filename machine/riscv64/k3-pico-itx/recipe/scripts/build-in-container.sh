#!/bin/sh
set -eu

linux_url=https://github.com/spacemit-com/linux-6.18.git
linux_commit=0ffac20d9ef93c572b649037213bbe20ef59a714
opensbi_url=https://github.com/spacemit-com/opensbi.git
opensbi_commit=e5fc30394ac18263fa045dcaef52f86f180ed512
buildroot_url=https://github.com/spacemit-com/buildroot.git
buildroot_commit=06a303b332a7216c6ca9360dd7c7f52a3fb8b1da
uboot_url=https://github.com/spacemit-com/uboot-2022.10.git
uboot_commit=6747f87ae4cd359ff6e22daa38b06c3ecc2fecb4
cross_compile=riscv64-unknown-linux-gnu-
jobs="${JOBS:-1}"

export SOURCE_DATE_EPOCH=1779807738
export KBUILD_BUILD_TIMESTAMP=2026-05-26T15:02:18Z
export KBUILD_BUILD_USER=spacemit
export KBUILD_BUILD_HOST=k3-sdk-v1.0.2
export KBUILD_BUILD_VERSION=1

clone_at()
{
    url="$1"
    commit="$2"
    destination="$3"

    git init -q "${destination}"
    git -C "${destination}" remote add origin "${url}"
    git -C "${destination}" fetch -q --depth=1 origin "${commit}"
    git -C "${destination}" checkout -q --detach FETCH_HEAD
    test "$(git -C "${destination}" rev-parse HEAD)" = "${commit}"
    test -z "$(git -C "${destination}" status --porcelain)"
}

mkdir -p /work/src /work/dl
clone_at "${linux_url}" "${linux_commit}" /work/src/linux
clone_at "${opensbi_url}" "${opensbi_commit}" /work/src/opensbi
clone_at "${buildroot_url}" "${buildroot_commit}" /work/src/buildroot
clone_at "${uboot_url}" "${uboot_commit}" /work/src/uboot

git -C /work/src/opensbi apply \
    /recipe/patches/opensbi/0001-sbi-guard-spacemit-platform-code.patch
install -m 0644 /recipe/configs/opensbi-qemu_defconfig \
    /work/src/opensbi/platform/generic/configs/qemu_defconfig
git -C /work/src/opensbi diff --check

git -C /work/src/uboot apply \
    /recipe/patches/uboot/0001-mmc-spacemit-allow-fixed-rate-input-clocks.patch \
    /recipe/patches/uboot/0002-mmc-sdhci-accept-completion-at-timeout-boundary.patch
git -C /work/src/uboot diff --check

make -C /work/src/linux O=/work/linux-out ARCH=riscv \
    CROSS_COMPILE="${cross_compile}" k3_defconfig
/work/src/linux/scripts/config --file /work/linux-out/.config \
    --set-str INITRAMFS_SOURCE ""
make -C /work/src/linux O=/work/linux-out ARCH=riscv \
    CROSS_COMPILE="${cross_compile}" olddefconfig
make -C /work/src/linux O=/work/linux-out ARCH=riscv \
    CROSS_COMPILE="${cross_compile}" -j"${jobs}" Image

make -C /work/src/opensbi O=/work/opensbi-out \
    CROSS_COMPILE="${cross_compile}" PLATFORM=generic \
    PLATFORM_DEFCONFIG=qemu_defconfig -j1 \
    /work/opensbi-out/platform/generic/firmware/fw_dynamic.bin

make -C /work/src/buildroot O=/work/buildroot-out \
    BR2_DEFCONFIG=/recipe/configs/k3-qemu-initramfs_defconfig defconfig
make -C /work/src/buildroot O=/work/buildroot-out \
    BR2_DL_DIR=/work/dl -j1

make -C /work/src/uboot O=/work/uboot-out \
    CROSS_COMPILE="${cross_compile}" k3_defconfig
/work/src/uboot/scripts/config --file /work/uboot-out/.config \
    --enable SYSCON \
    --enable RESET_SYSCON
make -C /work/src/uboot O=/work/uboot-out \
    CROSS_COMPILE="${cross_compile}" olddefconfig
make -C /work/src/uboot O=/work/uboot-out \
    CROSS_COMPILE="${cross_compile}" -j1 u-boot.bin

dtc -i /recipe/dts -I dts -O dtb -o /dist/k3-pico-itx-qemu.dtb \
    /recipe/dts/k3-pico-itx-qemu.dts
dtc -i /recipe/dts -I dts -O dtb \
    -o /dist/k3-pico-itx-qemu-linux-sd.dtb \
    /recipe/dts/k3-pico-itx-qemu-linux-sd.dts
dtc -i /recipe/dts -I dts -O dtb \
    -o /dist/k3-pico-itx-qemu-uboot.dtb \
    /recipe/dts/k3-pico-itx-qemu-uboot.dts
install -m 0644 /work/linux-out/arch/riscv/boot/Image /dist/Image
install -m 0644 \
    /work/opensbi-out/platform/generic/firmware/fw_dynamic.bin \
    /dist/fw_dynamic.bin
install -m 0644 /work/buildroot-out/images/rootfs.cpio.gz \
    /dist/k3-qemu-initramfs.cpio.gz
install -m 0644 /work/uboot-out/u-boot.bin /dist/u-boot.bin

sd_image=/dist/k3-qemu-sd.raw
bootfs_image=/work/k3-qemu-bootfs.fat
sd_files=/work/sd-files

rm -rf "${sd_files}"
mkdir -p "${sd_files}"
install -m 0644 /dist/Image "${sd_files}/Image"
install -m 0644 /dist/k3-pico-itx-qemu-linux-sd.dtb \
    "${sd_files}/k3-pico-itx-qemu-linux-sd.dtb"
install -m 0644 /dist/k3-qemu-initramfs.cpio.gz \
    "${sd_files}/k3-qemu-initramfs.cpio.gz"
install -m 0644 /recipe/configs/env_k3.txt "${sd_files}/env_k3.txt"
find "${sd_files}" -type f -exec touch -d "@${SOURCE_DATE_EPOCH}" {} +

rm -f "${sd_image}" "${sd_image}.xz" "${bootfs_image}"
truncate -s 128M "${sd_image}"
sgdisk --clear \
    --disk-guid=4b335344-0000-4000-8000-000000000001 \
    --new=1:2048:260095 \
    --typecode=1:0700 \
    --change-name=1:bootfs \
    --partition-guid=1:4b335344-0001-4000-8000-000000000001 \
    "${sd_image}"

truncate -s 132120576 "${bootfs_image}"
faketime "@${SOURCE_DATE_EPOCH}" \
    mkfs.vfat --invariant -F 32 -n K3BOOT -i 4b335144 "${bootfs_image}"
for file in Image k3-pico-itx-qemu-linux-sd.dtb \
    k3-qemu-initramfs.cpio.gz env_k3.txt; do
    faketime "@${SOURCE_DATE_EPOCH}" \
        mcopy -i "${bootfs_image}" "${sd_files}/${file}" "::${file}"
done
dd if="${bootfs_image}" of="${sd_image}" bs=512 seek=2048 conv=notrunc \
    status=none
xz --check=crc32 --threads=1 -9 --keep "${sd_image}"

cd /dist
sha256sum Image fw_dynamic.bin k3-qemu-initramfs.cpio.gz \
    k3-pico-itx-qemu.dtb k3-pico-itx-qemu-linux-sd.dtb \
    k3-pico-itx-qemu-uboot.dtb u-boot.bin k3-qemu-sd.raw \
    k3-qemu-sd.raw.xz \
    >SHA256SUMS
