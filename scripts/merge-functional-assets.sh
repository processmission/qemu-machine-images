#!/usr/bin/env bash

set -euo pipefail

if (( $# != 5 )); then
    echo "usage: $0 REPO_ROOT CANDIDATES_DIR BASE_DIR RELEASE_DIR UPLOAD_DIR" >&2
    exit 2
fi

readonly REPO_ROOT="$(realpath -e -- "$1")"
readonly CANDIDATES_ROOT="$(realpath -e -- "$2")"
readonly BASE_DIR="$3"
readonly RELEASE_ROOT="$(realpath -e -- "$4")"
readonly UPLOAD_ROOT="$(realpath -e -- "$5")"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if [[ "${BASE_DIR}" == - ]]; then
    readonly BASE_ROOT=-
else
    readonly BASE_ROOT="$(realpath -e -- "${BASE_DIR}")"
fi

declare -A expected_assets=()

merge_machine_assets() {
    local machine_conf="$1"
    local image
    local asset
    local manifest
    local candidate_present=0
    local source_root=-
    local source_path
    local line
    local listed_asset
    local -a functional_assets=()
    declare -A manifest_assets=()

    unset RELEASE_ASSET_PREFIX FUNCTIONAL_IMAGES
    # shellcheck disable=SC1090
    source "${machine_conf}"

    if ! declare -p FUNCTIONAL_IMAGES >/dev/null 2>&1; then
        return 0
    fi
    declare -p FUNCTIONAL_IMAGES 2>/dev/null | grep -q '^declare -a ' || \
        die "FUNCTIONAL_IMAGES must be an indexed array: ${machine_conf}"
    (( ${#FUNCTIONAL_IMAGES[@]} > 0 )) || \
        die "FUNCTIONAL_IMAGES must not be empty: ${machine_conf}"
    : "${RELEASE_ASSET_PREFIX:?RELEASE_ASSET_PREFIX is required}"
    [[ "${RELEASE_ASSET_PREFIX}" =~ ^[A-Za-z0-9_.-]+$ ]] || \
        die "invalid release asset prefix: ${RELEASE_ASSET_PREFIX}"

    manifest="${RELEASE_ASSET_PREFIX}--SHA256SUMS"
    expected_assets["${manifest}"]=1
    for image in "${FUNCTIONAL_IMAGES[@]}"; do
        [[ "${image}" =~ ^[A-Za-z0-9_.+-]+$ ]] || \
            die "invalid functional image name: ${image}"
        asset="${RELEASE_ASSET_PREFIX}--${image}"
        [[ -z "${expected_assets[${asset}]+present}" ]] || \
            die "duplicate functional asset: ${asset}"
        expected_assets["${asset}"]=1
        functional_assets+=("${asset}")
    done

    for asset in "${functional_assets[@]}" "${manifest}"; do
        if [[ -e "${CANDIDATES_ROOT}/${asset}" ]]; then
            candidate_present=1
        fi
    done

    if (( candidate_present )); then
        source_root="${CANDIDATES_ROOT}"
    elif [[ "${BASE_ROOT}" != - ]]; then
        source_root="${BASE_ROOT}"
    else
        die "no functional-test assets available for ${machine_conf}"
    fi

    for asset in "${functional_assets[@]}" "${manifest}"; do
        source_path="${source_root}/${asset}"
        [[ ! -L "${source_path}" && -f "${source_path}" ]] || \
            die "functional-test asset is incomplete: ${source_path}"
    done

    while IFS= read -r line; do
        [[ "${line}" =~ ^[[:xdigit:]]{64}[[:space:]]+\*?([A-Za-z0-9_.+-]+)$ ]] || \
            die "invalid functional checksum manifest: ${source_root}/${manifest}"
        listed_asset="${BASH_REMATCH[1]}"
        [[ -n "${expected_assets[${listed_asset}]+present}" ]] || \
            die "unexpected functional asset in manifest: ${listed_asset}"
        manifest_assets["${listed_asset}"]=$((
            ${manifest_assets[${listed_asset}]:-0} + 1
        ))
    done < "${source_root}/${manifest}"

    for asset in "${functional_assets[@]}"; do
        [[ "${manifest_assets[${asset}]:-0}" -eq 1 ]] || \
            die "functional checksum manifest is incomplete: ${asset}"
    done

    (
        cd -- "${source_root}"
        sha256sum --check --strict -- "${manifest}"
    )

    for asset in "${functional_assets[@]}" "${manifest}"; do
        cp -- "${source_root}/${asset}" "${RELEASE_ROOT}/${asset}"
        cp -- "${source_root}/${asset}" "${UPLOAD_ROOT}/${asset}"
    done
}

mkdir -p -- "${RELEASE_ROOT}" "${UPLOAD_ROOT}"
mapfile -t machine_confs < <(
    find "${REPO_ROOT}/machine" \
        -mindepth 3 \
        -maxdepth 3 \
        -type f \
        -name machine.conf \
        -print | sort
)

for machine_conf in "${machine_confs[@]}"; do
    merge_machine_assets "${machine_conf}"
done

for source_path in "${CANDIDATES_ROOT}"/*; do
    [[ -e "${source_path}" ]] || break
    [[ ! -L "${source_path}" && -f "${source_path}" ]] || \
        die "functional-test candidate is not a regular file: ${source_path}"
    asset="$(basename -- "${source_path}")"
    [[ -n "${expected_assets[${asset}]+present}" ]] || \
        die "unexpected functional-test candidate: ${source_path}"
done
