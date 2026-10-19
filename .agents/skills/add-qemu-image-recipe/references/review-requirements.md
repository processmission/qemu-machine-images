<!--
SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
SPDX-License-Identifier: MIT
-->

# Contribution requirements

Apply these requirements with the repository's current interfaces and
the user's requested delivery scope.

## Recipes and release artifacts

- **Upstream board support.** Check Buildroot's board support before
  creating a builder. Prefer a suitable upstream defconfig and focused
  BR2_EXTERNAL adaptations through the shared interface.
- **Official SDK integration.** Use the maintained vendor Buildroot
  extension, toolchain, patches, and packaging for SDK-specific support.
  Let Buildroot packages own firmware, Linux, and rootfs builds.
- **Device trees.** Start with official board sources and use focused
  includes, overlays, or patches for the requested images.
- **Hardware patches.** Describe the actual chip and capability in patch
  subjects. Check vendor identifiers and the selected source's APIs.
- **Build paths.** Use generic paths such as `/opt/<vendor-sdk>` and
  `/workspace` in containers.
- **Image tools.** Install machine dependencies and generate images in
  the build container. Keep board integration in the recipe and shared
  builder interfaces.
- **Archive contract.** Publish one versioned archive and checksum per
  machine. List the images needed by `run.sh` in `REQUIRED_IMAGES` and
  keep artifact selection and release reuse in the shared implementation.
- **Required formats.** Publish the formats consumed by the launcher.
  Outer archive compression already covers raw disk images.
- **Release completeness.** Verify every required image and the complete
  archive/checksum pair before accepting a release for reuse.
- **Source verification.** Preserve source-download hashes and the shared
  release-checksum flow.
- **Reproducibility.** Describe enabled settings accurately. Establish
  complete-output equality with independent clean builds before claiming
  reproducible images.

## Scope and validation

- Reuse the shared launcher, build, and release interfaces. Keep unrelated
  formatting and cleanup outside a machine contribution.
- Keep root build instructions generic and board-specific details beside
  the recipe. A board PR's release version belongs in `VERSION`.
- Validate with the fork's GitHub Actions build and the released images
  consumed by `run.sh`. Use the working QEMU binary supplied by the user.
- Keep personal boot drivers, Expect scripts, diagnostic programs, logs,
  and output images out of the contributed recipe.
- Use isolated outputs for any local build diagnosis. When checking an
  independent first boot, start from the packaged image contents;
  preserve guest-written state for intentional persistence checks.

## Versions and commits

- Follow the current [version and release contract][readme]. Use one
  repository version for all machine archives. New machines or boot
  modes use a minor version, compatible fixes use a patch version, and
  incompatible contracts use a major version.
- Check the current release state and prerequisite contributions. New
  images need a publishable version; published upstream assets remain
  immutable.
- Keep a new machine's recipe, configuration, patches, launcher, required
  documentation, and version consistent in its integration commit.
  Preserve the version change when revising that commit.
- Fold review corrections into the commit that introduced the issue.
  Independently useful prerequisites can precede the machine commit.
- Start a new machine with `BUILD_REVISION=1`. For existing machines,
  release-affecting input changes outside `build.hcl` require a revision
  update. A launcher change consuming identical images does not require
  a rebuild revision. Check PR and release selection separately.
- Keep commit bodies and patch mail descriptions within 72 characters.
  Use the configured Git name and email for the authored commit's
  `Signed-off-by`. Preserve source authorship and omit coauthor or
  automation attribution.
- Describe final sources, packaging, runtime behavior, and verified
  results in contribution messages. Respect explicit instructions to
  keep changes local until publication is requested.

[readme]: ../../../../README.md
