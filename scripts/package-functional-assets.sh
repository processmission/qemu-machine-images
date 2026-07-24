#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
    echo "usage: $0 MACHINE_CONF BUILD_OUTPUT DIST_DIR" >&2
    exit 2
fi

readonly MACHINE_CONF="$1"
readonly BUILD_OUTPUT="$2"
readonly DIST_DIR="$3"

[[ -r "${MACHINE_CONF}" ]] || {
    echo "machine configuration is not readable: ${MACHINE_CONF}" >&2
    exit 1
}

# shellcheck disable=SC1090
source "${MACHINE_CONF}"

: "${RELEASE_ASSET_PREFIX:?RELEASE_ASSET_PREFIX is required}"
if ! declare -p FUNCTIONAL_IMAGES >/dev/null 2>&1; then
    exit 0
fi
if ! declare -p FUNCTIONAL_IMAGES 2>/dev/null | grep -q '^declare -a '; then
    echo "FUNCTIONAL_IMAGES must be an indexed array" >&2
    exit 1
fi
if (( ${#FUNCTIONAL_IMAGES[@]} == 0 )); then
    echo "FUNCTIONAL_IMAGES must not be empty" >&2
    exit 1
fi
if [[ ! "${RELEASE_ASSET_PREFIX}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "invalid release asset prefix: ${RELEASE_ASSET_PREFIX}" >&2
    exit 1
fi

readonly OUTPUT_ROOT="$(realpath -e -- "${BUILD_OUTPUT}")"
[[ -d "${OUTPUT_ROOT}/images" ]] || {
    echo "images directory does not exist: ${BUILD_OUTPUT}/images" >&2
    exit 1
}
readonly IMAGES_DIR="$(realpath -e -- "${OUTPUT_ROOT}/images")"

mkdir -p -- "${DIST_DIR}"
readonly DIST_ROOT="$(realpath -e -- "${DIST_DIR}")"
readonly MANIFEST="${RELEASE_ASSET_PREFIX}--SHA256SUMS"
readonly MANIFEST_PATH="${DIST_ROOT}/${MANIFEST}"
readonly MANIFEST_TEMPORARY="${MANIFEST_PATH}.tmp"

declare -A seen_images=()
declare -a temporary_assets=()
trap 'rm -f -- "${MANIFEST_TEMPORARY}" "${temporary_assets[@]}"' EXIT
: > "${MANIFEST_TEMPORARY}"

for image in "${FUNCTIONAL_IMAGES[@]}"; do
    if [[ ! "${image}" =~ ^[A-Za-z0-9_.+-]+$ ]]; then
        echo "invalid functional image name: ${image}" >&2
        exit 1
    fi
    if [[ -n "${seen_images[$image]+present}" ]]; then
        echo "duplicate functional image name: ${image}" >&2
        exit 1
    fi
    seen_images["${image}"]=1

    source_path="${IMAGES_DIR}/${image}"
    [[ ! -L "${source_path}" && -f "${source_path}" ]] || {
        echo "functional image is not a regular file: ${image}" >&2
        exit 1
    }
    resolved_path="$(realpath -e -- "${source_path}")"
    case "${resolved_path}" in
        "${IMAGES_DIR}"/*) ;;
        *)
            echo "functional image resolves outside images directory: ${image}" >&2
            exit 1
            ;;
    esac

    asset="${RELEASE_ASSET_PREFIX}--${image}"
    asset_path="${DIST_ROOT}/${asset}"
    asset_temporary="${asset_path}.tmp"
    temporary_assets+=("${asset_temporary}")
    cp -- "${source_path}" "${asset_temporary}"
    mv -- "${asset_temporary}" "${asset_path}"
    (
        cd -- "${DIST_ROOT}"
        sha256sum "${asset}"
    ) >> "${MANIFEST_TEMPORARY}"
done

mv -- "${MANIFEST_TEMPORARY}" "${MANIFEST_PATH}"
printf '%s\n' "${MANIFEST}"
