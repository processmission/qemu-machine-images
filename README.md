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

`VERSION` records the version of the complete repository release. The current
value, `1.0.0`, maps to the Git tag and GitHub Release `v1.0.0`. Keeping one
version for the repository makes a release an atomic, testable set of machine
images. It also avoids separate tag namespaces and release workflows for every
machine.

Each supported machine has two release assets:

```text
<release-asset-prefix>-v<version>.tar.zst
<release-asset-prefix>-v<version>.tar.zst.sha256
```

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

## Publish a release

Push relevant image changes to `main` to start the release workflow:

```console
git push origin main
```

The workflow runs only when a push changes at least one of these paths:

```text
.dockerignore
.github/workflows/release.yml
VERSION
machine/**
scripts/**
```

Documentation-only changes, including changes to `README.md`, do not rebuild or
republish the images.

The workflow derives the fixed release tag `v1.0.0` from `VERSION`, discovers
machines from their `build.hcl` files, builds and assembles their declared
components, packages the required images, and verifies the checksum. Only
after every matrix build succeeds does it move the tag to the current commit
and create or update the matching GitHub Release, replacing its `.tar.zst` and
`.sha256` assets. This rolling-release model is not compatible with GitHub's
immutable releases option.

## Run a machine

Set `QEMU_EXECUTABLE` to an absolute path. The launcher downloads the release
asset and checksum, verifies them, extracts them below `.cache/`, and then
starts QEMU. For example, start sifive_u with:

```console
QEMU_EXECUTABLE=/absolute/path/to/qemu-system-riscv64 \
  ./machine/riscv64/sifive_u/run.sh
```

The launcher obtains the GitHub repository from the clone's `origin`. The
following optional variables support forks, older releases, and mirrors:

| Variable | Meaning |
| --- | --- |
| `QEMU_MACHINE_IMAGES_VERSION` | Release version without the leading `v` |
| `QEMU_MACHINE_IMAGES_REPOSITORY` | GitHub repository in `OWNER/REPO` form |
| `QEMU_MACHINE_IMAGES_RELEASE_BASE_URL` | Complete directory URL containing the assets |

Additional command-line arguments are appended to the QEMU command. For
example, `run.sh -S -s` starts paused with a GDB server.

Downloaded archives are cached in `.cache/downloads/`. Extracted images are
cached in `.cache/releases/<tag>/<architecture>/<machine>/`. Removing either
directory is safe; the launcher recreates it on the next run.
