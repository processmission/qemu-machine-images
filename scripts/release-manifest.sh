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
  release-manifest.sh merge REPO_ROOT RELEASE_TAG SOURCE_SHA CANDIDATES \
    BASE_TAG BASE_MANIFEST BASE_ASSETS RELEASE_DIR UPLOAD_DIR
  release-manifest.sh select REPO_ROOT RELEASE_TAG STATE_TAG MANIFEST \
    ASSETS REQUEST
  release-manifest.sh validate RELEASE_TAG MANIFEST
  release-manifest.sh verify REPO_ROOT RELEASE_TAG MANIFEST DIST_DIR
  release-manifest.sh verify-assets RELEASE_TAG MANIFEST RELEASE_DIR ASSETS
  release-manifest.sh verify-payload RELEASE_TAG MANIFEST RELEASE_DIR ASSETS
EOF
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "required command not found: $1"
}

validate_release_tag() {
    local release_tag="$1"

    [[ "${release_tag}" =~ \
        ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
        die "invalid release tag: ${release_tag}"
}

validate_source_sha() {
    local source_sha="$1"

    [[ "${source_sha}" =~ ^[0-9a-f]{40}$ ]] || \
        die "invalid source commit: ${source_sha}"
}

release_tag_is_newer() {
    local candidate="${1#v}"
    local base="${2#v}"
    local candidate_major
    local candidate_minor
    local candidate_patch
    local base_major
    local base_minor
    local base_patch

    IFS=. read -r \
        candidate_major candidate_minor candidate_patch <<< "${candidate}"
    IFS=. read -r base_major base_minor base_patch <<< "${base}"
    (( candidate_major > base_major )) ||
        { (( candidate_major == base_major )) &&
          (( candidate_minor > base_minor )); } ||
        { (( candidate_major == base_major )) &&
          (( candidate_minor == base_minor )) &&
          (( candidate_patch > base_patch )); }
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

archive_pair_digest() {
    local directory="$1"
    local asset="$2"
    local expected_digest="${3:-}"
    local archive="${directory}/${asset}"
    local checksum="${archive}.sha256"
    local checksum_sha256
    local actual_sha256

    [[ ! -L "${archive}" && -f "${archive}" ]] || \
        die "release archive is not a regular file: ${asset}"
    [[ ! -L "${checksum}" && -f "${checksum}" ]] || \
        die "release checksum is not a regular file: ${asset}.sha256"

    checksum_sha256="$(checksum_digest "${checksum}" "${asset}")"
    actual_sha256="$(file_digest "${archive}")"
    [[ "${actual_sha256}" == "${checksum_sha256}" ]] || \
        die "release checksum verification failed: ${asset}"
    if [[ -n "${expected_digest}" ]]; then
        [[ "${actual_sha256}" == "${expected_digest}" ]] || \
            die "manifest checksum verification failed: ${asset}"
    fi

    printf '%s\n' "${actual_sha256}"
}

copy_archive_pair() {
    local source_dir="$1"
    local source_asset="$2"
    local destination_dir="$3"
    local destination_asset="$4"
    local digest="$5"

    cp --archive --reflink=auto --sparse=always -- \
        "${source_dir}/${source_asset}" \
        "${destination_dir}/${destination_asset}"
    printf '%s  %s\n' "${digest}" "${destination_asset}" > \
        "${destination_dir}/${destination_asset}.sha256"
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
    local inventory

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
    inventory="$(machine_inventory "${repo_root}" "${release_tag}")"

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
    done <<< "${inventory}"

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
    local inventory_lines

    repo_root="$(realpath -e -- "$1")"
    dist_root="$(realpath -e -- "$4")"
    validate_release_tag "${release_tag}"
    validate_manifest "${release_tag}" "${manifest}"
    inventory_lines="$(machine_inventory "${repo_root}" "${release_tag}")"

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
    done <<< "${inventory_lines}"

    manifest_count="$(jq --raw-output '.machines | length' "${manifest}")"
    (( manifest_count == expected_count )) || \
        die "release manifest machine set is incomplete"
}

select_machines() {
    (( $# == 6 )) || usage

    local repo_root
    local release_tag="$2"
    local state_tag="$3"
    local manifest="$4"
    local assets="$5"
    local request="$6"
    local machine_dir
    local asset
    local build_hcl_sha256
    local published_asset
    local published_hcl_sha256
    local -a inventory=()
    local inventory_lines
    local -a selected=()
    declare -A known_machines=()
    declare -A published_assets=()

    repo_root="$(realpath -e -- "$1")"
    validate_release_tag "${release_tag}"
    if [[ "${state_tag}" != - ]]; then
        validate_release_tag "${state_tag}"
        if [[ "${state_tag}" != "${release_tag}" ]]; then
            release_tag_is_newer "${release_tag}" "${state_tag}" || \
                die "release tag is not newer than state tag: ${release_tag}"
        fi
    fi
    inventory_lines="$(machine_inventory "${repo_root}" "${release_tag}")"
    mapfile -t inventory <<< "${inventory_lines}"

    for entry in "${inventory[@]}"; do
        IFS=$'\t' read -r machine_dir asset build_hcl_sha256 <<< "${entry}"
        known_machines["${machine_dir}"]=1
    done

    case "${request}" in
        all)
            for entry in "${inventory[@]}"; do
                IFS=$'\t' read -r machine_dir asset build_hcl_sha256 \
                    <<< "${entry}"
                selected+=("${machine_dir}")
            done
            ;;
        auto)
            if [[ "${state_tag}" == - || "${manifest}" == - ||
                  "${assets}" == - ]]; then
                for entry in "${inventory[@]}"; do
                    IFS=$'\t' read -r machine_dir asset build_hcl_sha256 \
                        <<< "${entry}"
                    selected+=("${machine_dir}")
                done
            else
                validate_manifest "${state_tag}" "${manifest}"
                while IFS= read -r machine_dir; do
                    [[ -n "${known_machines[${machine_dir}]+present}" ]] || \
                        die "published machine no longer exists: ${machine_dir}"
                done < <(
                    jq --raw-output '.machines | keys[]' "${manifest}"
                )
                [[ -r "${assets}" ]] || \
                    die "release asset list is not readable: ${assets}"
                jq --exit-status '
                    type == "array" and all(.[]; type == "string")
                ' "${assets}" >/dev/null || \
                    die "invalid release asset list: ${assets}"
                while IFS= read -r asset; do
                    published_assets["${asset}"]=1
                done < <(jq --raw-output '.[]' "${assets}")

                for entry in "${inventory[@]}"; do
                    IFS=$'\t' read -r \
                        machine_dir asset build_hcl_sha256 <<< "${entry}"
                    published_hcl_sha256="$(
                        jq --raw-output \
                            --arg machine_dir "${machine_dir}" '
                                .machines[$machine_dir].build_hcl_sha256 // ""
                            ' "${manifest}"
                    )"
                    published_asset="$(
                        jq --raw-output \
                            --arg machine_dir "${machine_dir}" '
                                .machines[$machine_dir].asset // ""
                            ' "${manifest}"
                    )"
                    if [[ "${published_hcl_sha256}" != \
                              "${build_hcl_sha256}" ||
                          -z "${published_asset}" ||
                          -z "${published_assets[${published_asset}]+present}" ||
                          -z "${published_assets[${published_asset}.sha256]+present}" ]]; then
                        selected+=("${machine_dir}")
                    fi
                done
            fi
            ;;
        *)
            [[ "${request}" =~ \
                ^machine/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || \
                die "invalid machine selection: ${request}"
            [[ -n "${known_machines[${request}]+present}" ]] || \
                die "unknown machine requested: ${request}"
            selected+=("${request}")
            ;;
    esac

    jq --compact-output --null-input \
        '$ARGS.positional' --args "${selected[@]}"
}

merge_manifest() (
    (( $# == 9 )) || usage

    local repo_root
    local release_tag="$2"
    local source_sha="$3"
    local candidates_root
    local base_tag="$5"
    local base_manifest="$6"
    local base_assets="$7"
    local release_root
    local upload_root
    local manifest_name="qemu-machine-images-${release_tag}.json"
    local entries
    local temporary
    local machine_dir
    local asset
    local build_hcl_sha256
    local candidate_archive
    local candidate_checksum
    local candidate_present
    local asset_sha256
    local built_from
    local base_entry
    local base_asset
    local base_asset_sha256
    local base_hcl_sha256
    local base_built_from
    local upload_pair
    local inventory
    local candidate_file
    local candidate_name
    declare -A expected_candidates=()

    repo_root="$(realpath -e -- "$1")"
    candidates_root="$(realpath -e -- "$4")"
    release_root="$8"
    upload_root="$9"
    validate_release_tag "${release_tag}"
    validate_source_sha "${source_sha}"

    mkdir -p -- "${release_root}" "${upload_root}"
    release_root="$(realpath -e -- "${release_root}")"
    upload_root="$(realpath -e -- "${upload_root}")"
    [[ "${release_root}" != "${upload_root}" ]] || \
        die "release and upload directories must be different"
    [[ -z "$(find "${release_root}" -mindepth 1 -print -quit)" ]] || \
        die "release directory is not empty: ${release_root}"
    [[ -z "$(find "${upload_root}" -mindepth 1 -print -quit)" ]] || \
        die "upload directory is not empty: ${upload_root}"

    if [[ "${base_tag}" == - ]]; then
        [[ "${base_manifest}" == - && "${base_assets}" == - ]] || \
            die "base release inputs must all be absent"
    else
        validate_release_tag "${base_tag}"
        if [[ "${base_tag}" != "${release_tag}" ]]; then
            release_tag_is_newer "${release_tag}" "${base_tag}" || \
                die "release tag is not newer than base tag: ${release_tag}"
        fi
        [[ "${base_manifest}" != - && "${base_assets}" != - ]] || \
            die "base release inputs are incomplete"
        base_assets="$(realpath -e -- "${base_assets}")"
        validate_manifest "${base_tag}" "${base_manifest}"
    fi

    entries="$(mktemp "${release_root}/.manifest.entries.XXXXXX")"
    temporary="$(mktemp "${release_root}/.manifest.tmp.XXXXXX")"
    trap 'rm -f -- "${entries}" "${temporary}"' EXIT
    inventory="$(machine_inventory "${repo_root}" "${release_tag}")"

    while IFS=$'\t' read -r machine_dir asset build_hcl_sha256; do
        expected_candidates["${asset}"]=1
        candidate_archive="${candidates_root}/${asset}"
        candidate_checksum="${candidate_archive}.sha256"
        candidate_present=0
        if [[ -e "${candidate_archive}" || -e "${candidate_checksum}" ]]; then
            [[ -f "${candidate_archive}" && -f "${candidate_checksum}" ]] || \
                die "release candidate pair is incomplete: ${asset}"
            candidate_present=1
        fi

        base_entry=""
        base_asset=""
        base_asset_sha256=""
        base_hcl_sha256=""
        base_built_from=""
        if [[ "${base_tag}" != - ]]; then
            base_entry="$(
                jq --raw-output \
                    --arg machine_dir "${machine_dir}" '
                        .machines[$machine_dir] // empty |
                        [
                            .asset,
                            .asset_sha256,
                            .build_hcl_sha256,
                            .built_from
                        ] | @tsv
                    ' "${base_manifest}"
            )"
            if [[ -n "${base_entry}" ]]; then
                IFS=$'\t' read -r \
                    base_asset base_asset_sha256 base_hcl_sha256 \
                    base_built_from <<< "${base_entry}"
            fi
        fi

        upload_pair=0
        if (( candidate_present )); then
            asset_sha256="$(
                archive_pair_digest "${candidates_root}" "${asset}"
            )"
            built_from="${source_sha}"
            copy_archive_pair \
                "${candidates_root}" "${asset}" \
                "${release_root}" "${asset}" "${asset_sha256}"

            if [[ "${base_tag}" != "${release_tag}" ||
                  "${base_asset}" != "${asset}" ||
                  "${base_asset_sha256}" != "${asset_sha256}" ]]; then
                upload_pair=1
            elif [[ -n "${base_asset}" ]]; then
                archive_pair_digest \
                    "${base_assets}" "${base_asset}" \
                    "${base_asset_sha256}" >/dev/null
            fi
        else
            [[ -n "${base_asset}" ]] || \
                die "no release candidate or reusable asset for ${machine_dir}"
            [[ "${base_hcl_sha256}" == "${build_hcl_sha256}" ]] || \
                die "changed machine has no release candidate: ${machine_dir}"
            asset_sha256="$(
                archive_pair_digest \
                    "${base_assets}" "${base_asset}" \
                    "${base_asset_sha256}"
            )"
            built_from="${base_built_from}"
            copy_archive_pair \
                "${base_assets}" "${base_asset}" \
                "${release_root}" "${asset}" "${asset_sha256}"
            if [[ "${base_tag}" != "${release_tag}" ||
                  "${base_asset}" != "${asset}" ]]; then
                upload_pair=1
            fi
        fi

        if (( upload_pair )); then
            cp --archive -- \
                "${release_root}/${asset}" \
                "${release_root}/${asset}.sha256" \
                "${upload_root}/"
        fi

        jq --compact-output --null-input \
            --arg key "${machine_dir}" \
            --arg asset "${asset}" \
            --arg asset_sha256 "${asset_sha256}" \
            --arg build_hcl_sha256 "${build_hcl_sha256}" \
            --arg built_from "${built_from}" '
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
    done <<< "${inventory}"

    for candidate_file in "${candidates_root}"/*; do
        [[ -e "${candidate_file}" ]] || break
        [[ ! -L "${candidate_file}" && -f "${candidate_file}" ]] || \
            die "release candidate is not a regular file: ${candidate_file}"
        candidate_name="$(basename -- "${candidate_file}")"
        candidate_name="${candidate_name%.sha256}"
        [[ -n "${expected_candidates[${candidate_name}]+present}" ]] || \
            die "unexpected release candidate: ${candidate_file}"
    done

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
    mv -- "${temporary}" "${release_root}/${manifest_name}"
    rm -f -- "${entries}"
    trap - EXIT

    verify_manifest \
        "${repo_root}" "${release_tag}" \
        "${release_root}/${manifest_name}" "${release_root}"
    cp --archive -- \
        "${release_root}/${manifest_name}" "${upload_root}/${manifest_name}"
)

verify_published_assets() {
    (( $# == 5 )) || usage

    local release_tag="$1"
    local manifest="$2"
    local release_root
    local assets="$4"
    local require_manifest="$5"
    local name
    local digest
    local machine_dir
    local asset
    local asset_sha256
    local manifest_name="qemu-machine-images-${release_tag}.json"
    local expected_sha256
    declare -A published_digests=()

    validate_release_tag "${release_tag}"
    validate_manifest "${release_tag}" "${manifest}"
    release_root="$(realpath -e -- "$3")"
    [[ -r "${assets}" ]] || die "release asset data is not readable: ${assets}"
    jq --exit-status '
        type == "object" and
        (.assets | type == "array") and
        all(
            .assets[];
            (.name | type == "string") and
            (.digest | type == "string") and
            (.digest | test("^sha256:[0-9a-f]{64}$"))
        )
    ' "${assets}" >/dev/null || die "invalid published release asset data"

    while IFS=$'\t' read -r name digest; do
        [[ -z "${published_digests[${name}]+present}" ]] || \
            die "duplicate published release asset: ${name}"
        published_digests["${name}"]="${digest#sha256:}"
    done < <(jq --raw-output '.assets[] | [.name, .digest] | @tsv' "${assets}")

    while IFS=$'\t' read -r machine_dir asset asset_sha256; do
        [[ -n "${published_digests[${asset}]+present}" ]] || \
            die "published release asset is missing: ${asset}"
        [[ "${published_digests[${asset}]}" == "${asset_sha256}" ]] || \
            die "published release asset digest is incorrect: ${asset}"

        name="${asset}.sha256"
        [[ -n "${published_digests[${name}]+present}" ]] || \
            die "published release asset is missing: ${name}"
        expected_sha256="$(file_digest "${release_root}/${name}")"
        [[ "${published_digests[${name}]}" == "${expected_sha256}" ]] || \
            die "published release asset digest is incorrect: ${name}"
    done < <(
        jq --raw-output '
            .machines | to_entries[] |
            [.key, .value.asset, .value.asset_sha256] | @tsv
        ' "${manifest}"
    )

    if (( require_manifest )); then
        [[ -n "${published_digests[${manifest_name}]+present}" ]] || \
            die "published release asset is missing: ${manifest_name}"
        expected_sha256="$(file_digest "${release_root}/${manifest_name}")"
        [[ "${published_digests[${manifest_name}]}" == \
              "${expected_sha256}" ]] || \
            die "published release asset digest is incorrect: ${manifest_name}"
    fi
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
        merge) merge_manifest "$@" ;;
        select) select_machines "$@" ;;
        validate)
            (( $# == 2 )) || usage
            validate_release_tag "$1"
            validate_manifest "$1" "$2"
            ;;
        verify) verify_manifest "$@" ;;
        verify-assets)
            (( $# == 4 )) || usage
            verify_published_assets "$@" 1
            ;;
        verify-payload)
            (( $# == 4 )) || usage
            verify_published_assets "$@" 0
            ;;
        *) usage ;;
    esac
}

main "$@"
