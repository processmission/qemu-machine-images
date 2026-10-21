# QEMU machine images

This repository builds firmware and operating-system images and provides small
launchers for QEMU machines. Generated images are published as GitHub Release
assets.

## Repository layout

```text
.
├── VERSION
├── machine
│   └── <qemu-architecture>
│       └── <qemu-machine>
│           ├── build.hcl
│           ├── machine.conf
│           └── run.sh
└── scripts
    ├── Dockerfile.<project>
    ├── assemble-machine-images.sh
    ├── docker-bake.hcl
    ├── machine-image.sh
    └── package-machine-images.sh
```

The first directory below `machine/` is the QEMU architecture name. The next
directory identifies a QEMU machine. `machine.conf` is the common source of
the architecture, QEMU machine name, release asset prefix and required images.
`build.hcl` selects the independently built components and supplies their
machine-specific build arguments.

Shared launcher code in `scripts/machine-image.sh` locates, downloads,
verifies, and caches release images. Machine directories contain only their
metadata and machine-specific QEMU command line.

This convention keeps the repository-level documentation independent of the
set of supported machines.

## Versioning and release assets

`VERSION` records the version of the complete repository release. A release
version `<version>` maps to the Git tag and GitHub Release `v<version>`. Keeping
one version for the repository makes a release an atomic, testable set of machine
images. It also avoids separate tag namespaces and release workflows for every
machine.

Each supported machine has two release assets:

```text
<release-asset-prefix>-v<version>.tar.zst
<release-asset-prefix>-v<version>.tar.zst.sha256
```

The release also contains a machine manifest named
`qemu-machine-images-v<version>.json`. It records each machine's build
specification digest, archive digest, and source commit. The release workflow
uses this manifest as the authoritative state of the last successful
publication.

The checksum file uses the format emitted by `sha256sum`. The archive contains
exactly the files listed in the machine's `REQUIRED_IMAGES` array under a
top-level `images/` directory:

```text
images/
├── <required machine image>
└── ...
```

The Buildroot version is independent of the repository release version. It is
selected when building the container and can change without changing the
directory or launcher contract.

## Build a machine image

The Dockerfile requires a Buildroot defconfig name. For example, build the
image for QEMU sifive_u machine and export its `images/` directory with Docker
Buildx:

```console
docker buildx build \
  --file scripts/Dockerfile.buildroot \
  --build-arg BUILDROOT_DEFCONFIG=hifive_unleashed_defconfig \
  --output type=local,dest=output \
  .
```

The default Buildroot source is the official repository at release `2026.05`.
`BUILDROOT_REF` accepts a branch, tag, or commit. `BUILDROOT_URL` selects a
different Git repository when building from a fork or mirror:

```console
docker buildx build \
  --file scripts/Dockerfile.buildroot \
  --build-arg BUILDROOT_URL=https://example.com/buildroot.git \
  --build-arg BUILDROOT_REF=0123456789abcdef0123456789abcdef01234567 \
  --build-arg BUILDROOT_DEFCONFIG=hifive_unleashed_defconfig \
  --output type=local,dest=output \
  .
```

Some Buildroot trees compose a base defconfig with additional configuration
fragments. Set `BUILDROOT_CONFIG_FRAGMENTS` to a whitespace-separated list of
repository-relative fragment paths:

```console
docker buildx build \
  --file scripts/Dockerfile.buildroot \
  --build-arg BUILDROOT_DEFCONFIG=board_defconfig \
  --build-arg BUILDROOT_CONFIG_FRAGMENTS="configs/storage.config configs/network.config" \
  --output type=local,dest=output \
  .
```

When fragments are present, the builder runs the tree's
`support/kconfig/merge_config.sh` with the selected defconfig as its base and
keeps the generated configuration in the normal out-of-tree output directory.
Without fragments, the existing `make <defconfig>` behavior is unchanged.

To add board configurations, packages, patches, or overlays from a
[br2-external tree](https://buildroot.org/downloads/manual/manual.html#outside-br-custom),
set the `BUILDROOT_EXTERNAL_PATHS` build argument to its path relative to this
repository:

```console
docker buildx build \
  --file scripts/Dockerfile.buildroot \
  --build-arg BUILDROOT_EXTERNAL_PATHS=machine/riscv64/example/buildroot-external \
  --build-arg BUILDROOT_DEFCONFIG=example_defconfig \
  --output type=local,dest=output \
  .
```

Each tree must contain `external.desc`, `Config.in`, and `external.mk`.
Separate multiple local tree paths with a colon. Local trees are copied into
the builder and registered in the specified order; a defconfig in a later tree
overrides one with the same name in an earlier tree or in Buildroot. Use
`BR2_EXTERNAL_<NAME>_PATH` in configuration files and make rules to reference
files in a tree, where `<NAME>` comes from its `external.desc`.

To use a vendor-maintained Git repository, set `BUILDROOT_EXTERNAL_URL` and
`BUILDROOT_EXTERNAL_REF`. The revision is required and may be a commit, tag,
or branch; use a full commit ID for reproducible builds. Set the optional
`BUILDROOT_EXTERNAL_SUBDIR` when the external tree is below the repository
root:

```console
docker buildx build \
  --file scripts/Dockerfile.buildroot \
  --build-arg BUILDROOT_EXTERNAL_URL=https://example.com/vendor/br2-external.git \
  --build-arg BUILDROOT_EXTERNAL_REF=0123456789abcdef0123456789abcdef01234567 \
  --build-arg BUILDROOT_EXTERNAL_SUBDIR=buildroot-external \
  --build-arg BUILDROOT_DEFCONFIG=vendor_board_defconfig \
  --output type=local,dest=output \
  .
```

The complete vendor repository is checked out inside the builder, preserving
files outside the selected subdirectory. A remote tree is registered before
any local trees from `BUILDROOT_EXTERNAL_PATHS`, so local machine configurations
can override vendor defaults. The same arguments can be passed in a machine's
Docker Bake `args` map. Repository download and revision checkout failures stop
configuration. The builder passes the resolved local directories to Buildroot
through its native `BR2_EXTERNAL` variable.

Configuration fragments are resolved relative to Buildroot first. If a path
is absent there, external trees are searched, with the last matching tree
taking precedence. The external trees remain available throughout the build,
including package hooks and post-image scripts. Omitting both
`BUILDROOT_EXTERNAL_PATHS` and `BUILDROOT_EXTERNAL_URL` keeps the existing build
behavior.

Run the configuration integration tests against an existing Buildroot source
tree with `tests/buildroot-external.sh /path/to/buildroot`. These tests use
real Buildroot configuration commands without compiling a target toolchain.
Remote-source cases use local Git fixtures through `file://` URLs and do
not require network access.

For a component that is distributed only as a binary blob, `Dockerfile.blob`
downloads it, verifies its SHA-256 digest, and exports it under the file
name selected by the required `BLOB_FILENAME` argument:

```console
docker buildx build \
  --file scripts/Dockerfile.blob \
  --build-arg BLOB_URL=https://example.com/path/to/firmware \
  --build-arg BLOB_SHA256=<sha256-digest> \
  --build-arg BLOB_FILENAME=firmware.bin \
  --output type=local,dest=output \
  .
```

The exported file is `output/images/firmware.bin`. A machine `build.hcl` can
inherit the reusable `_blob` target and set these three arguments for a
specific vendor artifact.

Each machine's `build.hcl` inherits reusable component targets from
`scripts/docker-bake.hcl`. Build and assemble all components declared by a
machine with:

```console
docker buildx bake \
  --file scripts/docker-bake.hcl \
  --file machine/riscv64/sifive_u/build.hcl \
  release-components
scripts/assemble-machine-images.sh components output
```

Every machine build specification declares a `BUILD_REVISION`. The complete
`build.hcl` file is the release boundary for that machine. Increment the
revision when a shared builder, machine configuration, patch, or other input
requires a new image without otherwise changing the HCL build arguments:

```hcl
variable "BUILD_REVISION" {
  default = "2"
}
```

Changes that only affect a launcher and consume the same released images do
not require a revision update. A release-affecting change outside
`build.hcl` must update the corresponding build specification in the same
change.

The following sifive_u example packages the required files from an existing
Buildroot output directory:

```console
version="$(tr -d '[:space:]' < VERSION)"
scripts/package-machine-images.sh \
  machine/riscv64/sifive_u/machine.conf \
  "${BUILDROOT_OUTPUT}" \
  dist \
  "v${version}"
```

`BUILDROOT_OUTPUT` is the directory containing `images/`, not the `images/`
directory itself. Upload both generated files to the matching GitHub Release.

## Validate pull requests

Pull requests targeting `main` run the `Validate pull request` workflow when
opened, reopened, or updated. It checks the merge commit against its base
branch parent and selects builds independently of published release manifests:

- changes inside `machine/<architecture>/<machine>/` build that machine,
  including metadata, patches, finalizers, and launcher changes;
- changes to shared inputs, such as `scripts/`, `.github/`, `VERSION`, and
  `.dockerignore`, build all machines; unknown paths outside machine
  directories also build all machines;
- changes limited to `README.md`, `docs/`, license files, or `.gitignore`
  skip image builds;
- newly added or renamed machines are built, fully removed machines are
  skipped, and machines missing `build.hcl` or `machine.conf` fail validation.

PR and release builds call the same reusable `build-machine.yml` workflow.
Each selected machine runs Docker Bake, image assembly, finalization, and
packaging, including validation of every file in `REQUIRED_IMAGES`. Archives
and SHA-256 files are available for seven days in Actions artifacts named
`pr-<number>-<release-asset-prefix>`. PR builds use read-only repository
permissions and do not publish Releases or update tags.

Script tests and version validation run even when no images need rebuilding.
The final `PR image build` check succeeds only when preparation and all
selected builds succeed, or preparation confirms that no builds are needed.
Add this check to the `main` branch protection rule or ruleset as a required
status check to block merging failed builds. The workflow has no path filter,
so documentation-only PRs can still complete this required check.

Fork PRs use the `pull_request` event without repository secrets. Depending
on the repository's Actions settings, GitHub may require a maintainer to
approve a first-time contributor's workflow run. See
[GitHub's fork workflow settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository).

Run the selection and release-manifest regression tests locally with:

```console
tests/select-pr-machines.sh
tests/release-manifest.sh
```

PR validation does not replace the `BUILD_REVISION` update required for
release-affecting changes outside `build.hcl`.

## Publish a release

Push relevant image changes to `main` to start the release workflow:

```console
git push origin main
```

The workflow runs automatically only when a push changes one of these paths:

```text
VERSION
machine/**/build.hcl
```

Documentation-only changes, including changes to `README.md`, do not rebuild or
republish the images. Changes to shared build or packaging code must bump the
`BUILD_REVISION` of every affected machine. Workflow-only changes do not
trigger a release automatically.

The repository that runs the workflow determines the automatic policy:

- a push to `processmission/qemu-machine-images:main` requests an upstream
  release;
- a push in a fork builds the selected machine artifacts without publishing a
  Release.

The workflow downloads the latest release manifest and compares each current
`build.hcl` digest with the last successful state. A machine requires a new
build when:

- its build specification digest changed;
- either its archive or checksum is missing from the release; or
- no usable release manifest exists.

Manual dispatch defaults to build-only mode. It uploads run-scoped Actions
artifacts but never creates a Release, updates a manifest, or moves a tag. This
allows repeated test builds in a fork without consuming new version numbers:

```console
gh workflow run release.yml -f mode=build -f machine=all
gh workflow run release.yml \
  -f mode=build \
  -f machine=machine/riscv64/sifive_u
```

Manual release mode follows the policy of the repository that runs it:

- upstream allows publishing only an unpublished version or resuming its
  Draft Release; rebuilding an already published version fails before the
  build matrix starts and requires `VERSION` to be increased;
- a fork publishes a development prerelease and may overwrite its same-version
  assets, update its manifest, and move its tag.

```console
gh workflow run release.yml \
  -f mode=release \
  -f machine=machine/riscv64/sifive_u
```

When `VERSION` names a new release, unchanged machine archives are downloaded
from the previous release, verified, renamed for the new version, and reused
without rebuilding. Their checksum files are regenerated with the new asset
names.

Upstream assets remain mutable only in a Draft Release. The workflow publishes
the draft only after every supported machine has a verified archive/checksum
pair and the GitHub asset digests match the complete manifest. Publishing
finalizes the tag, and the workflow verifies that it resolves to the release
commit. Once published, the workflow never overwrites the upstream assets or
force-moves their tag.

GitHub release immutability only applies to releases published after the
repository policy is enabled, so it cannot protect the existing upstream
`v1.0.0` release retroactively. The workflow enforces its frozen state instead.
Future upstream releases can additionally use GitHub's immutable release
policy because all asset mutation happens before a draft is published.

Fork releases intentionally remain mutable development channels. Their GitHub
prerelease status and release notes identify them as rolling releases whose
assets and checksums may change.

Use a patch version for compatible image fixes, a minor version for new
machines or boot modes, and a major version for incompatible asset or launcher
contracts.

## Run a machine

Set `QEMU_EXECUTABLE` to an absolute path. The launcher downloads the release
asset and checksum, verifies them, extracts them below `.cache/`, and then
starts QEMU. For example, start sifive_u with:

```console
QEMU_EXECUTABLE=/absolute/path/to/qemu-system-riscv64 \
  ./machine/riscv64/sifive_u/run.sh
```

Each machine declares a default boot mode and the modes it supports. Omit the
mode to use the default, or select it explicitly as the first argument:

```console
QEMU_EXECUTABLE=/absolute/path/to/qemu-system-riscv64 \
  ./machine/riscv64/sifive_u/run.sh firmware
```

The launcher obtains the GitHub repository from the clone's `origin`. The
following optional variables support forks, older releases, and mirrors:

| Variable | Meaning |
| --- | --- |
| `QEMU_MACHINE_IMAGES_VERSION` | Release version without the leading `v` |
| `QEMU_MACHINE_IMAGES_REPOSITORY` | GitHub repository in `OWNER/REPO` form |
| `QEMU_MACHINE_IMAGES_RELEASE_BASE_URL` | Complete directory URL containing the assets |

Additional command-line arguments are appended to the QEMU command. For
example, `run.sh -S -s` starts the default boot mode paused with a GDB server.
Use `--` to separate an explicit boot mode from QEMU options, as in
`run.sh firmware -- -S -s`.

On each launch, the launcher checks the published checksum and refreshes the
cached archive and extracted images when it changes. If the checksum cannot
be reached, the launcher falls back to previously verified extracted images
when all files required by the selected boot mode are available.

Downloaded archives are cached in `.cache/downloads/`. Extracted images are
cached in `.cache/releases/<tag>/<architecture>/<machine>/`. Removing either
directory is safe; the launcher recreates it on the next run.
