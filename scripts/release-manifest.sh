#!/usr/bin/env bash

set -euo pipefail

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
usage:
  release-manifest.sh create REPO_ROOT RELEASE_TAG DIST_DIR SOURCE_SHA OUTPUT
  release-manifest.sh validate RELEASE_TAG MANIFEST
  release-manifest.sh verify REPO_ROOT RELEASE_TAG MANIFEST DIST_DIR
EOF
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "required command not found: $1"
}

validate_release_tag() {
    local release_tag="$1"

    [[ "${release_tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "invalid release tag: ${release_tag}"
}

validate_source_sha() {
    local source_sha="$1"

    [[ "${source_sha}" =~ ^[0-9a-f]{40}$ ]] || \
        die "invalid source commit: ${source_sha}"
}

checksum_digest() {
    local checksum="$1"
    local asset="$2"
    local -a lines=()

    mapfile -t lines < "${checksum}"
    if (( ${#lines[@]} != 1 )) ||
        [[ ! "${lines[0]}" =~ ^([[:xdigit:]]{64})[[:space:]]+(\*?)(.*)$ ]] ||
        [[ "${BASH_REMATCH[3]}" != "${asset}" ]]; then
        die "invalid checksum file for ${asset}"
    fi

    printf '%s\n' "${BASH_REMATCH[1],,}"
}

file_digest() {
    local file="$1"
    local digest

    digest="$(sha256sum -- "${file}")"
    printf '%s\n' "${digest%% *}"
}

machine_asset_prefix() {
    local machine_root="$1"
    local machine_conf="${machine_root}/machine.conf"

    [[ -r "${machine_conf}" ]] || \
        die "machine configuration is not readable: ${machine_conf}"

    (
        set -euo pipefail
        unset RELEASE_ASSET_PREFIX
        # shellcheck disable=SC1090
        source "${machine_conf}"
        : "${RELEASE_ASSET_PREFIX:?RELEASE_ASSET_PREFIX is required}"
        [[ "${RELEASE_ASSET_PREFIX}" =~ ^[A-Za-z0-9_.-]+$ ]] || {
            printf 'error: invalid release asset prefix: %s\n' \
                "${RELEASE_ASSET_PREFIX}" >&2
            exit 1
        }
        printf '%s\n' "${RELEASE_ASSET_PREFIX}"
    )
}

machine_inventory() {
    local repo_root="$1"
    local release_tag="$2"
    local -a build_files=()
    local build_file
    local relative_build_file
    local machine_dir
    local machine_root
    local asset_prefix
    local asset
    local build_hcl_sha256

    mapfile -t build_files < <(
        find "${repo_root}/machine" \
            -mindepth 3 \
            -maxdepth 3 \
            -type f \
            -name build.hcl \
            -print | sort
    )
    (( ${#build_files[@]} > 0 )) || die "no machine build.hcl files found"

    for build_file in "${build_files[@]}"; do
        relative_build_file="${build_file#"${repo_root}/"}"
        machine_dir="${relative_build_file%/build.hcl}"
        [[ "${machine_dir}" =~ ^machine/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || \
            die "invalid machine directory: ${machine_dir}"

        machine_root="${repo_root}/${machine_dir}"
        [[ -x "${machine_root}/run.sh" ]] || \
            die "machine launcher is not executable: ${machine_dir}"

        asset_prefix="$(machine_asset_prefix "${machine_root}")"
        asset="${asset_prefix}-${release_tag}.tar.zst"
        build_hcl_sha256="$(file_digest "${build_file}")"
        printf '%s\t%s\t%s\n' \
            "${machine_dir}" "${asset}" "${build_hcl_sha256}"
    done
}

validate_manifest() {
    local release_tag="$1"
    local manifest="$2"
    local version="${release_tag#v}"

    [[ -r "${manifest}" ]] || die "manifest is not readable: ${manifest}"
    jq --exit-status \
        --arg release_tag "${release_tag}" \
        --arg version "${version}" '
            type == "object" and
            (keys | sort) ==
                ["machines", "release_tag", "schema", "version"] and
            .schema == 1 and
            .release_tag == $release_tag and
            .version == $version and
            (.machines | type == "object") and
            (.machines | length > 0) and
            all(
                .machines | to_entries[];
                (.key | test(
                    "^machine/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"
                )) and
                (.value | type == "object") and
                (.value | keys | sort) == [
                    "asset",
                    "asset_sha256",
                    "build_hcl_sha256",
                    "built_from"
                ] and
                (.value.asset | type == "string") and
                (.value.asset | endswith("-" + $release_tag + ".tar.zst")) and
                (.value.asset_sha256 | test("^[0-9a-f]{64}$")) and
                (.value.build_hcl_sha256 | test("^[0-9a-f]{64}$")) and
                (.value.built_from | test("^[0-9a-f]{40}$"))
            ) and
            ([.machines[].asset] | length) ==
                ([.machines[].asset] | unique | length)
        ' "${manifest}" >/dev/null || \
        die "invalid release manifest: ${manifest}"
}

create_manifest() (
    (( $# == 5 )) || usage

    local repo_root
    local release_tag="$2"
    local dist_root
    local source_sha="$4"
    local output="$5"
    local output_dir
    local entries
    local temporary
    local machine_dir
    local asset
    local build_hcl_sha256
    local archive
    local checksum
    local expected_digest
    local actual_digest

    repo_root="$(realpath -e -- "$1")"
    dist_root="$(realpath -e -- "$3")"
    validate_release_tag "${release_tag}"
    validate_source_sha "${source_sha}"

    output_dir="$(dirname -- "${output}")"
    mkdir -p -- "${output_dir}"
    output_dir="$(realpath -e -- "${output_dir}")"
    output="${output_dir}/$(basename -- "${output}")"
    entries="$(mktemp "${output}.entries.XXXXXX")"
    temporary="$(mktemp "${output}.tmp.XXXXXX")"
    trap 'rm -f -- "${entries}" "${temporary}"' EXIT

    while IFS=$'\t' read -r machine_dir asset build_hcl_sha256; do
        archive="${dist_root}/${asset}"
        checksum="${archive}.sha256"
        [[ ! -L "${archive}" && -f "${archive}" ]] || \
            die "release archive is not a regular file: ${asset}"
        [[ ! -L "${checksum}" && -f "${checksum}" ]] || \
            die "release checksum is not a regular file: ${asset}.sha256"

        expected_digest="$(checksum_digest "${checksum}" "${asset}")"
        actual_digest="$(file_digest "${archive}")"
        [[ "${actual_digest}" == "${expected_digest}" ]] || \
            die "release checksum verification failed: ${asset}"

        jq --compact-output --null-input \
            --arg key "${machine_dir}" \
            --arg asset "${asset}" \
            --arg asset_sha256 "${actual_digest}" \
            --arg build_hcl_sha256 "${build_hcl_sha256}" \
            --arg built_from "${source_sha}" '
                {
                    key: $key,
                    value: {
                        asset: $asset,
                        asset_sha256: $asset_sha256,
                        build_hcl_sha256: $build_hcl_sha256,
                        built_from: $built_from
                    }
                }
            ' >> "${entries}"
    done < <(machine_inventory "${repo_root}" "${release_tag}")

    jq --sort-keys --slurp \
        --arg release_tag "${release_tag}" \
        --arg version "${release_tag#v}" '
            {
                schema: 1,
                version: $version,
                release_tag: $release_tag,
                machines: from_entries
            }
        ' "${entries}" > "${temporary}"
    validate_manifest "${release_tag}" "${temporary}"
    mv -- "${temporary}" "${output}"
    rm -f -- "${entries}"
    trap - EXIT
)

verify_manifest() {
    (( $# == 4 )) || usage

    local repo_root
    local release_tag="$2"
    local manifest="$3"
    local dist_root
    local inventory
    local machine_dir
    local expected_asset
    local expected_hcl_sha256
    local asset
    local asset_sha256
    local build_hcl_sha256
    local archive
    local checksum
    local checksum_sha256
    local actual_sha256
    local expected_count
    local manifest_count

    repo_root="$(realpath -e -- "$1")"
    dist_root="$(realpath -e -- "$4")"
    validate_release_tag "${release_tag}"
    validate_manifest "${release_tag}" "${manifest}"

    expected_count=0
    while IFS=$'\t' read -r \
        machine_dir expected_asset expected_hcl_sha256; do
        expected_count=$((expected_count + 1))
        inventory="$(
            jq --exit-status --raw-output \
                --arg machine_dir "${machine_dir}" '
                    .machines[$machine_dir] |
                    [
                        .asset,
                        .asset_sha256,
                        .build_hcl_sha256
                    ] | @tsv
                ' "${manifest}"
        )" || die "manifest does not contain machine: ${machine_dir}"
        IFS=$'\t' read -r \
            asset asset_sha256 build_hcl_sha256 <<< "${inventory}"

        [[ "${asset}" == "${expected_asset}" ]] || \
            die "unexpected release asset for ${machine_dir}: ${asset}"
        [[ "${build_hcl_sha256}" == "${expected_hcl_sha256}" ]] || \
            die "stale build specification for ${machine_dir}"

        archive="${dist_root}/${asset}"
        checksum="${archive}.sha256"
        [[ ! -L "${archive}" && -f "${archive}" ]] || \
            die "release archive is not a regular file: ${asset}"
        [[ ! -L "${checksum}" && -f "${checksum}" ]] || \
            die "release checksum is not a regular file: ${asset}.sha256"

        checksum_sha256="$(checksum_digest "${checksum}" "${asset}")"
        actual_sha256="$(file_digest "${archive}")"
        [[ "${actual_sha256}" == "${checksum_sha256}" ]] || \
            die "release checksum verification failed: ${asset}"
        [[ "${actual_sha256}" == "${asset_sha256}" ]] || \
            die "manifest checksum verification failed: ${asset}"
    done < <(machine_inventory "${repo_root}" "${release_tag}")

    manifest_count="$(jq --raw-output '.machines | length' "${manifest}")"
    (( manifest_count == expected_count )) || \
        die "release manifest machine set is incomplete"
}

main() {
    (( $# >= 1 )) || usage

    require_command jq
    require_command realpath
    require_command sha256sum

    local command="$1"
    shift
    case "${command}" in
        create) create_manifest "$@" ;;
        validate)
            (( $# == 2 )) || usage
            validate_release_tag "$1"
            validate_manifest "$1" "$2"
            ;;
        verify) verify_manifest "$@" ;;
        *) usage ;;
    esac
}

main "$@"
