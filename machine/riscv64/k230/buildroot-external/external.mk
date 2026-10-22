# The SDK overlays its U-Boot sources after the normal patch step
define K230_QEMU_CONFIGURE_UBOOT
	$(SED) 's/^#define CONFIG_LINUX_RUN_CORE_ID .*/#define CONFIG_LINUX_RUN_CORE_ID 0/' \
		$(@D)/board/canaan/common/sdk_autoconf.h
	$(SED) 's/timebase-frequency = <27000000>/timebase-frequency = <10000000>/' \
		$(@D)/arch/riscv/dts/k230.dtsi
	$(SED) 's/riscv,isa = "rv64imafdcvsu"/riscv,isa = "rv64imafdc"/' \
		$(@D)/arch/riscv/dts/k230.dtsi
endef
UBOOT_PRE_CONFIGURE_HOOKS += K230_QEMU_CONFIGURE_UBOOT
