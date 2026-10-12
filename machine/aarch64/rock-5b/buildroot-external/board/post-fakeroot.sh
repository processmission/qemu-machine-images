#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
# SPDX-License-Identifier: MIT

set -euo pipefail

target_dir="$1"
export PATH="${HOST_DIR}/bin:${PATH}"
release="$(cat "${BINARIES_DIR}/kernel-release.txt")"
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --numeric-owner \
    --owner=0 --group=0 -cJf "${BINARIES_DIR}/kernel-modules.tar.xz" \
    -C "${target_dir}" lib/modules
rm -rf "${target_dir:?}/lib/modules/${release}/kernel"
"${HOST_DIR}/sbin/depmod" -a -b "${target_dir}" "${release}"
