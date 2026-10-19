---
# SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
# SPDX-License-Identifier: MIT
name: add-qemu-image-recipe
description: >-
  Use when adding or updating QEMU machine-image recipes in this
  repository, integrating Buildroot or vendor BR2_EXTERNAL trees,
  validating packaged boot modes, or addressing recipe review feedback.
---

# QEMU Image Recipes

Build recipes through the repository's shared interfaces and validate
their released images with the machine launcher. Run commands from the
repository root.

## Select sources and boot modes

Read [README.md][readme] and the selected machine's files. Use
[sifive_u][sifive-u] for the shared Buildroot interface and
[phytium-pi][phytium-pi] for a vendor Buildroot tree with fragments.
When addressing a review, read the comments on that contribution.

- Check upstream Buildroot's board defconfig, source versions, patches,
  and image hooks before creating a builder. Prefer supported board
  configurations that provide the requested images.
- For hardware that requires a vendor SDK, preserve its maintained
  Buildroot integration, toolchain, component dependencies, and packaging.
  Check the toolchain's host requirements, target ISA, libc, ABI, and
  kernel headers.
- Use configuration fragments and `BR2_EXTERNAL` for board adaptations.
  Read [Buildroot integration][integration] for the shared builder's
  inputs, external-tree layout, configuration order, and image hooks.
- Define the machine name, supported boot modes, firmware inputs,
  console, CPU and RAM settings, storage, DTB, and load addresses.
  A serial-console initramfs normally needs BusyBox and its runtime
  libraries.

## Implement the repository interfaces

Keep board inputs under `machine/<architecture>/<qemu-machine>/`.

1. `machine.conf`: define `ARCHITECTURE`, `QEMU_MACHINE`,
   `RELEASE_ASSET_PREFIX`, `DEFAULT_BOOT_MODE`, `SUPPORTED_BOOT_MODES`,
   and `REQUIRED_IMAGES`. List each required release file once.
2. `build.hcl`: declare `release-components`, `OUTPUT_DIR`, a machine
   cache scope, and `BUILD_REVISION`. Start a new machine at revision `1`.
   Inherit `_buildroot` or `_blob` where their interfaces fit.
3. Component output: export an `images/` directory into
   `${OUTPUT_DIR}/<component>`. Keep filenames unique across components.
4. `run.sh`: reuse `machine_image_launcher_init`, `machine_image_prepare`,
   and `machine_image_exec` from `scripts/machine-image.sh`. Validate the
   selected mode's images and forward `MACHINE_IMAGE_QEMU_ARGUMENTS`.
   Require a working QEMU binary through an absolute `QEMU_EXECUTABLE`.
5. Image constraints: use `POWER_OF_TWO_IMAGES`, optional image size
   variables, and `GPT_IMAGES` through the shared finalizer as needed.
6. Board documentation: explain selected sources, build requirements,
   required QEMU support, and supported launch modes beside the recipe.

The shared build workflow runs assembly, finalization, and packaging in
that order. Each machine publishes one `<prefix>-v<version>.tar.zst`
archive and its `.sha256` file. The archive contains exactly
`REQUIRED_IMAGES` under `images/`, including the images used by `run.sh`.
Publish formats needed by the launcher; outer archive compression already
covers raw disk images.

Keep machine dependencies and image generation inside the build
container. Use Buildroot hooks for device-tree compilation, FIT creation,
compression, and vendor image formats. The shared finalizer handles its
declarative size and GPT operations.

Do not modify `.github/workflows/` to register a board, choose its runner,
install its tools, or add an artifact channel.

## Preserve source and hardware contracts

- Pin source revisions and verify downloaded toolchains, source archives,
  and required vendor blobs. Use generic container paths such as
  `/opt/<vendor-sdk>` and `/workspace`.
- Build DTBs from official board sources with focused includes,
  overlays, or patches for the requested images.
- Name hardware-support patches after the real chip or subsystem.
  Reserve QEMU-specific names for QEMU profiles and boot contracts.
- Keep patches applicable to the selected source, with meaningful mail
  headers, authorship, explanation, and sign-off. Check the selected
  source's APIs and configuration symbols when updating a patch.
- Verify release archives with the shared packaging checksums. Claim
  reproducible outputs only after comparing independent clean builds.

## Validate and contribute

Follow [recipe validation][validation] to build through the user's fork
on GitHub Actions and launch its images with `run.sh`. Exercise every
advertised boot mode using the supplied working QEMU binary. Report the
tested commit, workflow result, and observed boot behavior.

Keep local diagnostic scripts, logs, and images in a task directory
excluded through `.git/info/exclude`. Set `TMPDIR` inside that directory;
do not use `/tmp` or commit personal boot harnesses. Use real builds and
guests for validation.

Apply [contribution requirements][requirements] when preparing commits.
Keep each machine change complete, preserve prerequisite dependencies,
and fold its review corrections into the original integration commit.
Respect instructions to leave work uncommitted or unpushed. For an
authorized history rewrite, verify the remote head and push with an
explicit `--force-with-lease` expectation.

[readme]: ../../../README.md
[sifive-u]: ../../../machine/riscv64/sifive_u/build.hcl
[phytium-pi]: ../../../machine/aarch64/phytium-pi/build.hcl
[integration]: references/buildroot-integration.md
[validation]: references/validation.md
[requirements]: references/review-requirements.md
