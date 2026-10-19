<!--
SPDX-FileCopyrightText: Copyright (c) 2026 Process Mission
SPDX-License-Identifier: MIT
-->

# Validate a recipe

Build on GitHub Actions in the user's fork, then boot the resulting
images through `run.sh` with a working QEMU binary supplied through
`QEMU_EXECUTABLE`.

## Build in the fork

Set `FORK_REPOSITORY` to the fork's `OWNER/REPO`, `FORK_REMOTE` to its
verified Git remote, and `MACHINE_DIR` to the recipe directory. Use the
current recipe branch as `BRANCH`. Enable Actions in the fork if needed.

Run ShellCheck on changed shell scripts, `git diff --check`, and patch
application checks against the selected clean component sources before
pushing the recipe.

For an authorized fork development release, build all machines to
provide the complete release manifest:

```bash
BRANCH="$(git branch --show-current)"
git push "$FORK_REMOTE" "$BRANCH"
gh workflow run release.yml \
  --repo "$FORK_REPOSITORY" --ref "$BRANCH" \
  -f mode=release -f machine=all
gh run list --repo "$FORK_REPOSITORY" \
  --workflow release.yml --branch "$BRANCH" \
  --event workflow_dispatch --limit 5 \
  --json databaseId,headSha,status,conclusion,url
```

Once the fork has a verified release manifest and reusable assets for
every other unchanged machine, `-f machine="$MACHINE_DIR"` can select a
targeted rebuild.

Use the run whose `headSha` matches the pushed commit. Inspect its status
and failed jobs using its `RUN_ID`:

```bash
gh run view "$RUN_ID" --repo "$FORK_REPOSITORY" \
  --json headSha,status,conclusion,url
gh run view "$RUN_ID" --repo "$FORK_REPOSITORY" --log-failed
```

The workflow runs Docker Bake, assembly, finalization, and packaging,
including checks for `REQUIRED_IMAGES`. Confirm it succeeds and the
matching fork release contains the machine archive and checksum:

```bash
RELEASE_TAG="v$(tr -d '[:space:]' < VERSION)"
gh release view "$RELEASE_TAG" --repo "$FORK_REPOSITORY" \
  --json assets,isDraft,isPrerelease,url
```

Fork `mode=release` publishes a development prerelease and updates its
same-version assets and tag. Use it when that publication is authorized.
`mode=build` and pull-request validation produce Actions artifacts only;
`QEMU_MACHINE_IMAGES_REPOSITORY` downloads from GitHub Releases. A
build-only run therefore establishes cloud build and packaging results,
while the repository-based launch requires the matching release assets.

## Launch the fork's images

Set `BOOT_MODE` to a mode declared in `SUPPORTED_BOOT_MODES`, and use the
working QEMU binary's absolute path:

```bash
QEMU_EXECUTABLE="$QEMU_EXECUTABLE" \
QEMU_MACHINE_IMAGES_REPOSITORY="$FORK_REPOSITORY" \
QEMU_MACHINE_IMAGES_VERSION="${RELEASE_TAG#v}" \
  "$MACHINE_DIR/run.sh" "$BOOT_MODE"
```

The launcher downloads the archive and checksum, verifies them, extracts
the required images, and starts QEMU. Check serial startup, the intended
userspace, kernel and board identity, and basic guest file access for
each advertised mode. For a firmware boot mode, confirm that it loads
the next stage and reaches the intended userspace.

If a previous guest changed cached writable images, move that machine's
extracted cache directory aside after QEMU exits before an independent
boot check. The launcher will extract the archive again. Retain modified
images when testing persistence.

Report the tested commit, successful Actions run, release version, boot
modes, and observed results. Keep any local diagnostic scripts and logs
in an excluded task directory.
