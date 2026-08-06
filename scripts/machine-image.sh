#!/usr/bin/env bash

machine_image_die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

machine_image_require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        machine_image_die "required command not found: $1"
}

machine_image_exec() {
    (( $# > 0 )) || machine_image_die "machine_image_exec requires a command"

    {
        printf 'QEMU command:'
        printf ' %q' "$@"
        printf '\n'
    } >&2
    exec "$@"
}

machine_image_launcher_init() {
    (( $# >= 1 )) || \
        machine_image_die "machine_image_launcher_init requires a launcher"

    local launcher="$1"
    local machine_dir
    shift

    machine_dir="$(
        CDPATH= cd -- "$(dirname -- "${launcher}")" && pwd
    )"
    MACHINE_IMAGE_MACHINE_DIR="${machine_dir}"
    MACHINE_IMAGE_REPO_ROOT="$(
        CDPATH= cd -- "${machine_dir}/../../.." && pwd
    )"

    # shellcheck disable=SC1090
    source "${machine_dir}/machine.conf"

    [[ -n "${QEMU_EXECUTABLE:-}" ]] || machine_image_die \
        "QEMU_EXECUTABLE must name the absolute path to qemu-system-${ARCHITECTURE}"
    [[ "${QEMU_EXECUTABLE}" = /* ]] || \
        machine_image_die "QEMU_EXECUTABLE must be an absolute path"
    [[ -x "${QEMU_EXECUTABLE}" ]] || \
        machine_image_die "QEMU executable is not executable: ${QEMU_EXECUTABLE}"

    MACHINE_IMAGE_QEMU_ARGUMENTS=("$@")
}

machine_image_github_repository() {
    local repo_root="$1"
    local repository="${QEMU_MACHINE_IMAGES_REPOSITORY:-}"
    local origin

    if [[ -z "${repository}" ]]; then
        machine_image_require_command git
        origin="$(git -C "${repo_root}" remote get-url origin 2>/dev/null || true)"
        [[ -n "${origin}" ]] || machine_image_die \
            "cannot determine repository; set QEMU_MACHINE_IMAGES_REPOSITORY=OWNER/REPO"

        case "${origin}" in
            git@github.com:*) repository="${origin#git@github.com:}" ;;
            ssh://git@github.com/*) repository="${origin#ssh://git@github.com/}" ;;
            https://github.com/*) repository="${origin#https://github.com/}" ;;
            http://github.com/*) repository="${origin#http://github.com/}" ;;
            *) machine_image_die "origin is not a GitHub repository: ${origin}" ;;
        esac
    fi

    repository="${repository#https://github.com/}"
    repository="${repository#http://github.com/}"
    repository="${repository%.git}"
    repository="${repository%/}"

    [[ "${repository}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || \
        machine_image_die \
            "invalid repository '${repository}'; expected OWNER/REPO"
    printf '%s\n' "${repository}"
}

machine_image_download() {
    local url="$1"
    local output="$2"
    local temporary="${output}.part"

    rm -f -- "${temporary}"
    if ! curl \
        --connect-timeout 10 \
        --fail \
        --location \
        --retry 3 \
        --retry-max-time 30 \
        --show-error \
        --silent \
        --output "${temporary}" \
        "${url}"; then
        rm -f -- "${temporary}"
        return 1
    fi
    mv -- "${temporary}" "${output}"
}

machine_image_checksum_digest() {
    if (( $# != 2 )); then
        machine_image_die \
            "machine_image_checksum_digest requires a checksum and asset"
    fi

    local checksum="$1"
    local asset="$2"
    local -a lines=()

    mapfile -t lines < "${checksum}"
    if (( ${#lines[@]} != 1 )) ||
        [[ ! "${lines[0]}" =~ ^([[:xdigit:]]{64})[[:space:]]+(\*?)(.*)$ ]] ||
        [[ "${BASH_REMATCH[3]}" != "${asset}" ]]; then
        machine_image_die "invalid checksum file for ${asset}"
    fi

    printf '%s\n' "${BASH_REMATCH[1],,}"
}

machine_image_checksum_matches() {
    if (( $# != 2 )); then
        machine_image_die \
            "machine_image_checksum_matches requires a file and checksum"
    fi

    local file="$1"
    local expected="$2"
    local actual

    [[ -f "${file}" ]] || return 1
    actual="$(sha256sum -- "${file}")" || return 1
    actual="${actual%% *}"
    [[ "${actual,,}" == "${expected,,}" ]]
}

machine_image_pad_to_power_of_two() {
    local image="$1"
    local size
    local padded_size=1

    machine_image_require_command stat
    machine_image_require_command truncate

    size="$(stat --format=%s -- "${image}")"
    [[ "${size}" =~ ^[1-9][0-9]*$ ]] || \
        machine_image_die "invalid image size for ${image}: ${size}"

    while (( padded_size < size )); do
        (( padded_size < 4611686018427387904 )) || \
            machine_image_die "image is too large to pad: ${image}"
        padded_size=$((padded_size * 2))
    done

    if (( padded_size != size )); then
        truncate --size="${padded_size}" -- "${image}"
    fi
}

machine_image_prepare() {
    if (( $# < 5 )); then
        machine_image_die \
            "machine_image_prepare requires machine metadata and image files"
    fi

    local repo_root="$1"
    local architecture="$2"
    local machine="$3"
    local asset_prefix="$4"
    shift 4
    local required_images=("$@")
    local required_image

    [[ "${architecture}" =~ ^[A-Za-z0-9_.-]+$ ]] || \
        machine_image_die "invalid architecture: ${architecture}"
    [[ "${machine}" =~ ^[A-Za-z0-9_.-]+$ ]] || \
        machine_image_die "invalid machine: ${machine}"
    [[ "${asset_prefix}" =~ ^[A-Za-z0-9_.-]+$ ]] || \
        machine_image_die "invalid release asset prefix: ${asset_prefix}"
    for required_image in "${required_images[@]}"; do
        case "${required_image}" in
            ""|/*|.|..|../*|*/./*|*/../*|*/.|*/..)
                machine_image_die "invalid required image path: ${required_image}"
                ;;
        esac
    done

    local version="${QEMU_MACHINE_IMAGES_VERSION:-}"
    if [[ -z "${version}" ]]; then
        [[ -r "${repo_root}/VERSION" ]] || \
            machine_image_die "cannot read repository VERSION"
        version="$(tr -d '[:space:]' < "${repo_root}/VERSION")"
    fi
    [[ "${version}" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || \
        machine_image_die "invalid release version: ${version}"

    local release_tag="v${version}"
    local asset="${asset_prefix}-${release_tag}.tar.zst"
    local download_dir="${repo_root}/.cache/downloads/${release_tag}"
    local release_dir="${repo_root}/.cache/releases/${release_tag}/${architecture}/${machine}"
    local complete_marker="${release_dir}/.complete"
    local archive="${download_dir}/${asset}"
    local archive_candidate="${archive}.candidate"
    local checksum="${archive}.sha256"
    local image_dir="${release_dir}/images"
    local release_base_url
    local expected_checksum
    local cached_checksum=""
    local cache_available=1
    local cache_complete=1

    if [[ -n "${QEMU_MACHINE_IMAGES_RELEASE_BASE_URL:-}" ]]; then
        release_base_url="${QEMU_MACHINE_IMAGES_RELEASE_BASE_URL%/}"
    else
        local repository
        repository="$(machine_image_github_repository "${repo_root}")"
        release_base_url="https://github.com/${repository}/releases/download/${release_tag}"
    fi

    if [[ -f "${complete_marker}" ]]; then
        cached_checksum="$(< "${complete_marker}")"
    fi
    [[ "${cached_checksum}" =~ ^[[:xdigit:]]{64}$ ]] || cache_available=0
    for required_image in "${required_images[@]}"; do
        [[ -f "${image_dir}/${required_image}" ]] || cache_available=0
    done

    machine_image_require_command curl
    mkdir -p -- "${download_dir}" "$(dirname -- "${release_dir}")"
    if ! machine_image_download \
        "${release_base_url}/${asset}.sha256" "${checksum}"; then
        if (( cache_available )); then
            printf 'warning: cannot refresh release checksum; using verified cached images\n' \
                >&2
            MACHINE_IMAGE_DIR="${image_dir}"
            return 0
        fi
        machine_image_die \
            "cannot refresh release checksum and no verified cached images are available"
    fi
    expected_checksum="$(machine_image_checksum_digest "${checksum}" "${asset}")"

    cache_complete="${cache_available}"
    [[ "${cached_checksum}" == "${expected_checksum}" ]] || cache_complete=0

    if (( ! cache_complete )); then
        machine_image_require_command sha256sum
        machine_image_require_command tar
        machine_image_require_command zstd

        if ! machine_image_checksum_matches \
            "${archive}" "${expected_checksum}"; then
            if [[ -f "${archive}" ]]; then
                printf 'cached release asset is stale or invalid; refreshing %s\n' \
                    "${asset}" >&2
            else
                printf 'downloading release asset: %s\n' "${asset}" >&2
            fi

            rm -f -- "${archive_candidate}"
            if ! machine_image_download \
                "${release_base_url}/${asset}" "${archive_candidate}"; then
                if (( cache_available )); then
                    printf 'warning: cannot refresh release asset; using verified cached images\n' \
                        >&2
                    MACHINE_IMAGE_DIR="${image_dir}"
                    return 0
                fi
                machine_image_die \
                    "cannot download release asset and no verified cached images are available"
            fi
            if ! machine_image_checksum_matches \
                "${archive_candidate}" "${expected_checksum}"; then
                rm -f -- "${archive_candidate}"
                machine_image_die \
                    "downloaded release asset checksum verification failed: ${asset}"
            fi
            mv -- "${archive_candidate}" "${archive}"
        fi

        local staging_dir
        staging_dir="$(mktemp -d "${release_dir}.tmp.XXXXXX")"
        if ! (
            trap 'rm -rf -- "${staging_dir}"' EXIT
            tar \
                --extract \
                --use-compress-program=zstd \
                --file="${archive}" \
                --directory="${staging_dir}" \
                --no-same-owner \
                --no-same-permissions
            for required_image in "${required_images[@]}"; do
                [[ -f "${staging_dir}/images/${required_image}" ]] || {
                    printf 'error: release archive does not contain images/%s\n' \
                        "${required_image}" >&2
                    exit 1
                }
            done

            printf '%s\n' "${expected_checksum}" > "${staging_dir}/.complete"
            rm -rf -- "${release_dir}"
            mv -- "${staging_dir}" "${release_dir}"
        ); then
            machine_image_die "failed to extract release archive"
        fi
    fi

    MACHINE_IMAGE_DIR="${image_dir}"
}
