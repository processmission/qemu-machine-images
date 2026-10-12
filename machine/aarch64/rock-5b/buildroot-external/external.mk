# SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
# SPDX-License-Identifier: MIT

UBOOT_DEPENDENCIES += host-xz

define ROCK5B_QEMU_INSTALL_KERNEL_METADATA
	$(INSTALL) -m 0644 $(@D)/.config $(BINARIES_DIR)/kernel.config
	$(INSTALL) -m 0644 $(@D)/include/config/kernel.release \
		$(BINARIES_DIR)/kernel-release.txt
	printf 'linux-%s\n' '$(LINUX_VERSION)' > $(BINARIES_DIR)/kernel-revision.txt
endef
LINUX_POST_INSTALL_IMAGES_HOOKS += ROCK5B_QEMU_INSTALL_KERNEL_METADATA
