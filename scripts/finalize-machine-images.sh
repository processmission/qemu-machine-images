#!/usr/bin/env bash

set -euo pipefail

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

readonly FINALIZER="${MACHINE_ROOT}/finalize-images.sh"
if [[ ! -e "${FINALIZER}" && ! -L "${FINALIZER}" ]]; then
    printf 'no image finalizer for %s\n' "${MACHINE_ROOT}"
    exit 0
fi

[[ ! -L "${FINALIZER}" && -f "${FINALIZER}" && -x "${FINALIZER}" ]] || {
    echo "machine image finalizer is not an executable regular file: ${FINALIZER}" >&2
    exit 1
}

"${FINALIZER}" "${IMAGES_ROOT}"
