#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 BUILDROOT_DIR OUTPUT_DIR" >&2
    exit 2
fi

buildroot_dir=$1
output_dir=$2

if [ -z "${BUILDROOT_CONFIG_FRAGMENTS}" ]; then
    make -C "${buildroot_dir}" O="${output_dir}" "${BUILDROOT_DEFCONFIG}"
else
    mkdir -p "${output_dir}"
    set -- "configs/${BUILDROOT_DEFCONFIG}"
    set -f
    for fragment in ${BUILDROOT_CONFIG_FRAGMENTS}; do
        case "${fragment}" in
            -*|/*|.|..|../*|*/./*|*/../*|*/.|*/..|*[!A-Za-z0-9_./-]*)
                echo "invalid Buildroot config fragment: ${fragment}" >&2
                exit 1
                ;;
        esac
        test -r "${buildroot_dir}/${fragment}" ||
            { echo "Buildroot config fragment is not readable: ${fragment}" >&2; exit 1; }
        set -- "$@" "${fragment}"
    done
    cd -- "${buildroot_dir}"
    ./support/kconfig/merge_config.sh -O "${output_dir}" "$@"
fi
