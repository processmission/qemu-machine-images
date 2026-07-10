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
    curl \
        --fail \
        --location \
        --retry 3 \
        --show-error \
        --silent \
        --output "${temporary}" \
        "${url}"
    mv -- "${temporary}" "${output}"
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
    local checksum="${archive}.sha256"
    local image_dir="${release_dir}/images"
    local cache_complete=1

    [[ -f "${complete_marker}" ]] || cache_complete=0
    for required_image in "${required_images[@]}"; do
        [[ -f "${image_dir}/${required_image}" ]] || cache_complete=0
    done

    if (( ! cache_complete )); then
        machine_image_require_command curl
        machine_image_require_command sha256sum
        machine_image_require_command tar
        machine_image_require_command zstd

        local release_base_url
        if [[ -n "${QEMU_MACHINE_IMAGES_RELEASE_BASE_URL:-}" ]]; then
            release_base_url="${QEMU_MACHINE_IMAGES_RELEASE_BASE_URL%/}"
        else
            local repository
            repository="$(machine_image_github_repository "${repo_root}")"
            release_base_url="https://github.com/${repository}/releases/download/${release_tag}"
        fi

        mkdir -p -- "${download_dir}" "$(dirname -- "${release_dir}")"
        [[ -f "${archive}" ]] || \
            machine_image_download "${release_base_url}/${asset}" "${archive}"
        machine_image_download \
            "${release_base_url}/${asset}.sha256" "${checksum}"

        if ! (
            cd -- "${download_dir}"
            sha256sum --check --strict "${asset}.sha256"
        ); then
            rm -f -- "${archive}"
            machine_image_download "${release_base_url}/${asset}" "${archive}"
            (
                cd -- "${download_dir}"
                sha256sum --check --strict "${asset}.sha256"
            ) || machine_image_die "release checksum verification failed"
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

            rm -rf -- "${release_dir}"
            mv -- "${staging_dir}" "${release_dir}"
            touch -- "${complete_marker}"
        ); then
            machine_image_die "failed to extract release archive"
        fi
    fi

    MACHINE_IMAGE_DIR="${image_dir}"
}
