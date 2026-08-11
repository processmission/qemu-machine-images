#!/usr/bin/env bash

set -euo pipefail

readonly MAXIMUM_IMAGE_SIZE=$((4 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024))

die() {
    echo "error: $*" >&2
    exit 1
}

validate_image_path() {
    local image="$1"

    case "${image}" in
        ""|/*|.|..|../*|*/./*|*/../*|*/.|*/..)
            die "invalid image path: ${image}"
            ;;
    esac
}

validate_bounded_size() {
    local value="$1"
    local description="$2"

    [[ "${value}" =~ ^[1-9][0-9]*$ ]] || \
        die "${description} is not a positive integer: ${value}"
    if (( ${#value} > ${#MAXIMUM_IMAGE_SIZE} )) ||
        { (( ${#value} == ${#MAXIMUM_IMAGE_SIZE} )) &&
            [[ "${value}" > "${MAXIMUM_IMAGE_SIZE}" ]]; }; then
        die "${description} is too large: ${value}"
    fi
}

next_power_of_two() {
    local size="$1"
    local image="$2"
    local padded_size=1

    while (( padded_size < size )); do
        # Stop before another doubling would overflow signed 64-bit arithmetic
        (( padded_size < MAXIMUM_IMAGE_SIZE )) || \
            die "image is too large to finalize: ${image}"
        padded_size=$((padded_size * 2))
    done

    printf '%s\n' "${padded_size}"
}

image_size_variable() {
    local image="$1"
    local variable="${image^^}"

    # Derive names such as SDCARD_IMG_SIZE from release image paths
    variable="${variable//[^A-Z0-9]/_}_SIZE"
    [[ "${variable}" =~ ^[A-Z_][A-Z0-9_]*$ ]] || \
        die "image path does not canonicalize to a variable name: ${image}"

    printf '%s\n' "${variable}"
}

finalize_image() {
    local image="$1"
    local target_size="$2"
    local repair_gpt="$3"
    local source_path="${IMAGES_ROOT}/${image}"
    local original_size

    [[ ! -L "${source_path}" && -f "${source_path}" ]] || \
        die "image is not a regular file: ${image}"

    local resolved_path
    resolved_path="$(realpath -e -- "${source_path}")"
    case "${resolved_path}" in
        "${IMAGES_ROOT}"/*) ;;
        *) die "image resolves outside images directory: ${image}" ;;
    esac

    original_size="$(stat --format='%s' -- "${source_path}")"
    validate_bounded_size "${original_size}" "image size for ${image}"

    if [[ -z "${target_size}" ]]; then
        target_size="$(next_power_of_two "${original_size}" "${image}")"
    else
        validate_bounded_size "${target_size}" "target size for ${image}"
        (( (target_size & (target_size - 1)) == 0 )) || \
            die "target size is not a power of two for ${image}: ${target_size}"
        (( target_size >= original_size )) || \
            die "target size is smaller than ${image}: ${target_size}"
    fi

    if (( target_size == original_size )) && (( ! repair_gpt )); then
        printf '%s already has a power-of-two size (%s bytes)\n' \
            "${source_path}" "${target_size}"
        return 0
    fi

    local temporary_dir
    local temporary_image

    # Finalize a copy so failures leave the assembled image unchanged
    temporary_dir="$(
        mktemp --directory --tmpdir="${IMAGES_ROOT}" .image-finalize.XXXXXX
    )"
    temporary_image="${temporary_dir}/image"

    if ! (
        set -e
        trap 'rm -rf -- "${temporary_dir}"' EXIT

        cp --archive --reflink=auto --sparse=always -- \
            "${source_path}" "${temporary_image}"
        truncate --size="${target_size}" -- "${temporary_image}"

        if (( repair_gpt )); then
            # Relocate the backup GPT to the new end before validation
            sgdisk -e "${temporary_image}"
            sgdisk -v "${temporary_image}"
        fi

        local final_size
        final_size="$(stat --format='%s' -- "${temporary_image}")"
        if (( final_size != target_size )); then
            echo \
                "final image has an unexpected size: ${final_size} bytes" \
                >&2
            exit 1
        fi

        mv --force -- "${temporary_image}" "${source_path}"
    ); then
        die "failed to finalize image: ${image}"
    fi

    printf 'finalized %s from %s to %s bytes\n' \
        "${source_path}" "${original_size}" "${target_size}"
}

if (( $# != 2 )); then
    echo "usage: $0 MACHINE_DIR IMAGES_DIR" >&2
    exit 2
fi

readonly MACHINE_ROOT="$(realpath -e -- "$1")"
readonly IMAGES_ROOT="$(realpath -e -- "$2")"

[[ -d "${MACHINE_ROOT}" ]] || {
    echo "machine directory does not exist: $1" >&2
    exit 1
}
[[ -d "${IMAGES_ROOT}" ]] || {
    echo "images directory does not exist: $2" >&2
    exit 1
}

# Keep the hook for transformations that cannot be expressed as metadata
readonly FINALIZER="${MACHINE_ROOT}/finalize-images.sh"
if [[ ! -e "${FINALIZER}" && ! -L "${FINALIZER}" ]]; then
    printf 'no machine-specific image finalizer for %s\n' "${MACHINE_ROOT}"
else
    [[ ! -L "${FINALIZER}" && -f "${FINALIZER}" && -x "${FINALIZER}" ]] || {
        echo \
            "machine image finalizer is not an executable regular file: ${FINALIZER}" \
            >&2
        exit 1
    }

    "${FINALIZER}" "${IMAGES_ROOT}"
fi

# Apply declarative constraints after machine-specific transformations
readonly MACHINE_CONF="${MACHINE_ROOT}/machine.conf"
[[ -r "${MACHINE_CONF}" ]] || \
    die "machine configuration is not readable: ${MACHINE_CONF}"

# shellcheck disable=SC1090
source "${MACHINE_CONF}"

declaration="$(declare -p REQUIRED_IMAGES 2>/dev/null || true)"
[[ "${declaration}" == "declare -a "* ]] || \
    die "REQUIRED_IMAGES must be an indexed array"
(( ${#REQUIRED_IMAGES[@]} > 0 )) || \
    die "REQUIRED_IMAGES must not be empty"

declaration="$(declare -p POWER_OF_TWO_IMAGES 2>/dev/null || true)"
if [[ -z "${declaration}" ]]; then
    POWER_OF_TWO_IMAGES=()
elif [[ "${declaration}" != "declare -a "* ]]; then
    die "POWER_OF_TWO_IMAGES must be an indexed array"
fi

declaration="$(declare -p GPT_IMAGES 2>/dev/null || true)"
if [[ -z "${declaration}" ]]; then
    GPT_IMAGES=()
elif [[ "${declaration}" != "declare -a "* ]]; then
    die "GPT_IMAGES must be an indexed array"
fi

declare -A required_images=()
for image in "${REQUIRED_IMAGES[@]}"; do
    validate_image_path "${image}"
    [[ -z "${required_images[${image}]+present}" ]] || \
        die "duplicate required image path: ${image}"
    required_images["${image}"]=1
done

declare -A power_of_two_images=()
for image in "${POWER_OF_TWO_IMAGES[@]}"; do
    validate_image_path "${image}"
    [[ -z "${power_of_two_images[${image}]+present}" ]] || \
        die "duplicate power-of-two image path: ${image}"
    [[ -n "${required_images[${image}]+present}" ]] || \
        die "power-of-two image is not required for release: ${image}"
    power_of_two_images["${image}"]=1
done

declare -A gpt_images=()
for image in "${GPT_IMAGES[@]}"; do
    validate_image_path "${image}"
    [[ -z "${gpt_images[${image}]+present}" ]] || \
        die "duplicate GPT image path: ${image}"
    [[ -n "${power_of_two_images[${image}]+present}" ]] || \
        die "GPT image is not a power-of-two image: ${image}"
    gpt_images["${image}"]=1
done

# Resolve every generated variable name before modifying any image
declare -A size_variable_images=()
for image in "${POWER_OF_TWO_IMAGES[@]}"; do
    size_variable="$(image_size_variable "${image}")"
    if [[ -n "${size_variable_images[${size_variable}]+present}" ]]; then
        die "duplicate image size variable: ${size_variable}"
    fi
    size_variable_images["${size_variable}"]="${image}"

    if [[ -v "${size_variable}" ]]; then
        declaration="$(declare -p "${size_variable}")"
        [[ "${declaration}" == "declare -- "* ]] || \
            die "${size_variable} must be a scalar assignment"
        validate_bounded_size \
            "${!size_variable}" "target size for ${image}"
    fi
done

for image in "${POWER_OF_TWO_IMAGES[@]}"; do
    size_variable="$(image_size_variable "${image}")"
    target_size=""
    if [[ -v "${size_variable}" ]]; then
        target_size="${!size_variable}"
    fi
    repair_gpt=0
    [[ -z "${gpt_images[${image}]+present}" ]] || repair_gpt=1
    finalize_image "${image}" "${target_size}" "${repair_gpt}"
done
