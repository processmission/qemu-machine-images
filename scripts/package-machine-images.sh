#!/usr/bin/env bash

set -euo pipefail

if (( $# != 4 )); then
    echo \
        "usage: $0 MACHINE_CONF BUILD_OUTPUT DIST_DIR RELEASE_TAG" >&2
    exit 2
fi

readonly MACHINE_CONF="$1"
readonly BUILD_OUTPUT="$2"
readonly DIST_DIR="$3"
readonly RELEASE_TAG="$4"

[[ -r "${MACHINE_CONF}" ]] || {
    echo "machine configuration is not readable: ${MACHINE_CONF}" >&2
    exit 1
}

# shellcheck disable=SC1090
source "${MACHINE_CONF}"

: "${RELEASE_ASSET_PREFIX:?RELEASE_ASSET_PREFIX is required}"
if ! declare -p REQUIRED_IMAGES 2>/dev/null | grep -q '^declare -a '; then
    echo "REQUIRED_IMAGES must be an indexed array" >&2
    exit 1
fi
if (( ${#REQUIRED_IMAGES[@]} == 0 )); then
    echo "REQUIRED_IMAGES must not be empty" >&2
    exit 1
fi
if [[ ! "${RELEASE_ASSET_PREFIX}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "invalid release asset prefix: ${RELEASE_ASSET_PREFIX}" >&2
    exit 1
fi
if [[ ! "${RELEASE_TAG}" =~ ^v[0-9A-Za-z][0-9A-Za-z._-]*$ ]]; then
    echo "invalid release tag: ${RELEASE_TAG}" >&2
    exit 1
fi

readonly OUTPUT_ROOT="$(realpath -e -- "${BUILD_OUTPUT}")"
[[ -d "${OUTPUT_ROOT}/images" ]] || {
    echo "images directory does not exist: ${BUILD_OUTPUT}/images" >&2
    exit 1
}
readonly IMAGES_DIR="$(realpath -e -- "${OUTPUT_ROOT}/images")"

declare -A seen_images=()
declare -a archive_paths=()
for image in "${REQUIRED_IMAGES[@]}"; do
    case "${image}" in
        ""|/*|.|..|../*|*/./*|*/../*|*/.|*/..)
            echo "invalid required image path: ${image}" >&2
            exit 1
            ;;
    esac
    if [[ -n "${seen_images[$image]+present}" ]]; then
        echo "duplicate required image path: ${image}" >&2
        exit 1
    fi
    seen_images["${image}"]=1

    source_path="${IMAGES_DIR}/${image}"
    [[ ! -L "${source_path}" && -f "${source_path}" ]] || {
        echo "required image is not a regular file: ${image}" >&2
        exit 1
    }
    resolved_path="$(realpath -e -- "${source_path}")"
    case "${resolved_path}" in
        "${IMAGES_DIR}"/*) ;;
        *)
            echo "required image resolves outside images directory: ${image}" >&2
            exit 1
            ;;
    esac

    archive_paths+=("images/${image}")
done

mkdir -p -- "${DIST_DIR}"
readonly DIST_ROOT="$(realpath -e -- "${DIST_DIR}")"
readonly ASSET="${RELEASE_ASSET_PREFIX}-${RELEASE_TAG}.tar.zst"
readonly ARCHIVE="${DIST_ROOT}/${ASSET}"
readonly ARCHIVE_TEMPORARY="${ARCHIVE}.tmp"
readonly CHECKSUM="${ARCHIVE}.sha256"
readonly CHECKSUM_TEMPORARY="${CHECKSUM}.tmp"

trap 'rm -f -- "${ARCHIVE_TEMPORARY}" "${CHECKSUM_TEMPORARY}"' EXIT

tar \
    --create \
    --use-compress-program="zstd -T0 -10" \
    --file="${ARCHIVE_TEMPORARY}" \
    --directory="${OUTPUT_ROOT}" \
    --no-recursion \
    -- \
    "${archive_paths[@]}"
mv -- "${ARCHIVE_TEMPORARY}" "${ARCHIVE}"

(
    cd -- "${DIST_ROOT}"
    sha256sum "${ASSET}" > "${CHECKSUM_TEMPORARY}"
)
mv -- "${CHECKSUM_TEMPORARY}" "${CHECKSUM}"

printf '%s\n' "${ASSET}"
