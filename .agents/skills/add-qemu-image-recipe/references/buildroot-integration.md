<!--
SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
SPDX-License-Identifier: MIT
-->

# Buildroot integration

Use this reference for source selection, BR2_EXTERNAL configuration,
firmware, device trees, and image generation. Check symbols and package
rules in the selected Buildroot revision.

## Select an upstream board or vendor SDK

Inspect upstream `configs/*defconfig`, the board directory, patches,
source hashes, and image hooks. Prefer an existing board configuration
with focused fragments for the required boot modes. Keep its toolchain,
kernel, and U-Boot versions together unless the requested support needs
a component change.

For vendor support, use the official SDK's Buildroot extension or overlay,
defconfigs, toolchain, patches, and packaging tools. Preserve Buildroot's
package dependencies, source checks, and toolchain-header compatibility.
Personal checkout paths and `*_OVERRIDE_SRCDIR` settings do not belong in
a distributable recipe.

Use [the shared builder][builder] for supported configurations. Board
fragments, packages, patches, and hooks can live in an external tree.
A vendor SDK with additional setup can provide that setup in its own
component stage while invoking the SDK's normal Buildroot workflow.

## Connect BR2_EXTERNAL to the shared builder

The BR2_EXTERNAL integration exposes the arguments below through the
machine target's `args` map. Check `scripts/Dockerfile.buildroot` and
`scripts/configure-buildroot.sh` on the selected branch for this support
before adding an external-tree recipe.

| Argument | Meaning |
| --- | --- |
| `BUILDROOT_URL` | Git repository containing Buildroot |
| `BUILDROOT_REF` | Selected Buildroot revision |
| `BUILDROOT_DEFCONFIG` | Defconfig name in Buildroot or an external tree |
| `BUILDROOT_CONFIG_FRAGMENTS` | Whitespace-separated fragment paths |
| `BUILDROOT_EXTERNAL_PATHS` | Colon-separated local tree paths |
| `BUILDROOT_EXTERNAL_URL` | Git repository containing a vendor tree |
| `BUILDROOT_EXTERNAL_REF` | Required revision of that vendor repository |
| `BUILDROOT_EXTERNAL_SUBDIR` | Optional tree path inside that repository |

Local tree paths are relative to the repository's Docker build context.
Use a machine-owned directory such as `buildroot-external/` containing:

- `external.desc`: a unique `name` using letters, digits, and underscores,
  plus an optional `desc`.
- `Config.in`: additional Kconfig entries; it may be empty when the
  profile uses only existing packages.
- `external.mk`: package definitions, dependency additions, and hooks;
  it may be empty when no make rules are needed.
- `configs/`: a full defconfig or fragments for an existing board.
- `board/` and `patches/`: device-tree adaptations, rootfs files, hooks,
  component patches, and source hashes as needed.

For example, extend an upstream board through the shared Bake target:

```hcl
target "buildroot" {
  inherits = ["_buildroot"]
  args = {
    BUILDROOT_DEFCONFIG = "rock5b_defconfig"
    BUILDROOT_EXTERNAL_PATHS = "machine/aarch64/rock-5b/buildroot-external"
    BUILDROOT_CONFIG_FRAGMENTS = "configs/rock5b_qemu.config"
  }
}
```

The machine's complete build specification also supplies its source pin,
component output, cache settings, and release build revision.

For a vendor tree, provide its Git URL and full commit ID. The optional
subdirectory selects the tree while the complete checkout remains
available for SDK files referenced outside that subdirectory. Local
trees may be combined with the vendor tree.

Configuration order matters:

1. The remote vendor tree is registered first, followed by local trees
   in `BUILDROOT_EXTERNAL_PATHS` order.
2. A later external tree's defconfig overrides a same-named defconfig
   in an earlier tree or in Buildroot.
3. Fragment paths are resolved in Buildroot first. When absent there,
   the last external tree containing that path supplies the fragment.
4. Fragments are merged in their listed order using Buildroot's Kconfig
   tools, followed by its normal configuration resolution.

Use `$(BR2_EXTERNAL_<NAME>_PATH)` in configuration and make rules, with
`<NAME>` from `external.desc`. Hooks can use the exported shell variable
`BR2_EXTERNAL_<NAME>_PATH`. The shared helper preserves external trees
inside the builder for subsequent make invocations and image hooks;
refer to these registered paths for board files.

## Keep component configuration native

- Extend the upstream board defconfig with focused fragments. Preserve
  upstream fragments and patch/hash directories when adding local ones;
  assigning these list-valued settings replaces their previous values.
- Let Buildroot supply host dependencies. Declare image tools through
  package selections or dependencies in `external.mk` so they exist when
  the corresponding hook runs.
- Use package configuration to select firmware outputs. Check
  `boot/uboot/uboot.mk` for the selected revision; adding a target to
  `BR2_TARGET_UBOOT_CUSTOM_MAKEOPTS` may leave the default `all` target
  active.
- Keep the board's native firmware packaging. For SPL boot, export the
  SPL binary and subsequent stage images under the names used by
  `run.sh`. Where supported, `BR2_TARGET_UBOOT_SPL` selects SPL export.
  For binman-generated U-Boot FITs, use `BR2_TARGET_UBOOT_USE_BINMAN`
  with `BR2_TARGET_UBOOT_FORMAT_ITB`; binman produces the FIT during the
  normal build, so a separate `u-boot.itb` make target is unnecessary.
- Prefer upstream DTS files with a focused include, overlay, or patch.
  Check configuration symbols, clock identifiers, early-device tags,
  and the selected source's DT build rules.
- For driver additions, use vendor identifiers and documented hardware
  capabilities. Check the selected API's field conventions; Linux SPI
  NOR versions with an obsolete `flash_info.name` require it to remain
  unset in new entries.

## Choose image hooks

Use Buildroot's hooks and vendor image tools inside the build container:

- Package image-install hooks export component metadata from the actual
  package build directory, such as the kernel configuration and release.
- Post-build hooks customize the installed root filesystem.
- Post-fakeroot hooks customize the filesystem image's staging copy.
  When shipping loadable modules separately, archive and remove them
  here so subsequent builds retain the complete installed target tree.
  Preserve built-in module metadata and regenerate indexes with the
  matching host `depmod`.
- Post-image hooks apply DT overlays and assemble FIT, flash, or vendor
  images from generated files in `BINARIES_DIR`. Use Buildroot's host
  tools from `HOST_DIR`.

Derive flash capacity, offsets, compression support, read lengths, and
load addresses from the recipe's firmware contract. Check the final FIT
against its allocated region and the decompressed kernel extent against
other loaded images. Preserve the native firmware layout when placing
additional payloads in the same flash image.

Export component files under `images/` for shared assembly and packaging.
Use `POWER_OF_TWO_IMAGES` and `GPT_IMAGES` for the shared finalizer's
supported storage constraints.

[builder]: ../../../../scripts/Dockerfile.buildroot
