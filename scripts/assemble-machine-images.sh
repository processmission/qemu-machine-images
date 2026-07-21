#!/usr/bin/env bash

set -euo pipefail

if (( $# != 2 )); then
    echo "usage: $0 COMPONENTS_DIR BUILD_OUTPUT" >&2
    exit 2
fi

readonly COMPONENTS_ROOT="$(realpath -e -- "$1")"
readonly BUILD_OUTPUT="$2"

[[ -d "${COMPONENTS_ROOT}" ]] || {
    echo "components directory does not exist: $1" >&2
    exit 1
}

mkdir -p -- "${BUILD_OUTPUT}/images"
readonly OUTPUT_ROOT="$(realpath -e -- "${BUILD_OUTPUT}")"
readonly IMAGES_DIR="${OUTPUT_ROOT}/images"

if [[ -n "$(find "${IMAGES_DIR}" -mindepth 1 -print -quit)" ]]; then
    echo "output images directory is not empty: ${IMAGES_DIR}" >&2
    exit 1
fi

invalid_component="$(
    find "${COMPONENTS_ROOT}" \
        -mindepth 1 \
        -maxdepth 1 \
        ! -type d \
        -print \
        -quit
)"
if [[ -n "${invalid_component}" ]]; then
    echo "component output is not a directory: ${invalid_component}" >&2
    exit 1
fi

declare -a component_dirs=()
mapfile -d '' component_dirs < <(
    find "${COMPONENTS_ROOT}" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -print0 | sort -z
)
if (( ${#component_dirs[@]} == 0 )); then
    echo "components directory is empty: ${COMPONENTS_ROOT}" >&2
    exit 1
fi

file_count=0
for component_dir in "${component_dirs[@]}"; do
    component_name="${component_dir##*/}"
    component_images="${component_dir}/images"
    [[ ! -L "${component_images}" && -d "${component_images}" ]] || {
        echo "component does not export an images directory: ${component_name}" >&2
        exit 1
    }

    invalid_image="$(
        find "${component_images}" \
            -mindepth 1 \
            ! -type d \
            ! -type f \
            ! -type l \
            -print \
            -quit
    )"
    if [[ -n "${invalid_image}" ]]; then
        echo "unsupported component image type: ${invalid_image}" >&2
        exit 1
    fi

    declare -a component_images_entries=()
    mapfile -d '' component_images_entries < <(
        find "${component_images}" \
            \( -type f -o -type l \) \
            -print0 | sort -z
    )
    if (( ${#component_images_entries[@]} == 0 )); then
        echo "component exports no images: ${component_name}" >&2
        exit 1
    fi

    for source_path in "${component_images_entries[@]}"; do
        relative_path="${source_path#"${component_images}/"}"
        destination_path="${IMAGES_DIR}/${relative_path}"
        if [[ -e "${destination_path}" || -L "${destination_path}" ]]; then
            echo \
                "component image collision at ${relative_path}: ${component_name}" \
                >&2
            exit 1
        fi

        mkdir -p -- "$(dirname -- "${destination_path}")"
        cp --archive --no-target-directory -- \
            "${source_path}" "${destination_path}"
        (( file_count += 1 ))
    done
done

printf 'assembled %d image(s) from %d component(s)\n' \
    "${file_count}" "${#component_dirs[@]}"
