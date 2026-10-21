#!/bin/sh

set -eu
set -f

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

validate_relative_path() {
    case "$1" in
        ""|-*|/*|.|..|../*|*/./*|*/../*|*/.|*/..|*[!A-Za-z0-9_./-]*)
            die "invalid $2: $1"
            ;;
    esac
}

validate_external_tree() {
    [ -d "$1" ] || die "external tree is not a directory: $1"
    for metadata in external.desc Config.in external.mk; do
        [ -f "$1/${metadata}" ] || die "external tree is missing ${metadata}: $1"
    done
}

[ "$#" -eq 3 ] || die "usage: $0 BUILDROOT_DIR OUTPUT_DIR CONTEXT_DIR"
buildroot_dir=$(realpath -e -- "$1")
mkdir -p -- "$2"
output_dir=$(realpath -e -- "$2")
context_dir=$(realpath -e -- "$3")

case "${BUILDROOT_DEFCONFIG:-}" in
    ""|*[!A-Za-z0-9_.-]*) die 'BUILDROOT_DEFCONFIG must be a defconfig name' ;;
esac

external_paths=
external_root="$(dirname -- "${output_dir}")/external"
external_url=${BUILDROOT_EXTERNAL_URL:-}
external_ref=${BUILDROOT_EXTERNAL_REF:-}
external_subdir=${BUILDROOT_EXTERNAL_SUBDIR:-}
if [ -n "${external_url}" ]; then
    case "${external_url}" in
        -*) die 'BUILDROOT_EXTERNAL_URL must be a Git repository URL' ;;
    esac
    case "${external_ref}" in
        ""|-*) die 'BUILDROOT_EXTERNAL_REF must name a Git revision' ;;
    esac
    if [ -n "${external_subdir}" ] && [ "${external_subdir}" != . ]; then
        validate_relative_path "${external_subdir}" 'external repository subdirectory'
    fi

    repository_dir="${external_root}/remote"
    [ ! -e "${repository_dir}" ] || die "external destination already exists: ${repository_dir}"
    mkdir -p -- "${external_root}"
    git init -q "${repository_dir}"
    git -C "${repository_dir}" remote add origin "${external_url}"
    git -C "${repository_dir}" fetch --depth=1 origin "${external_ref}"
    git -C "${repository_dir}" checkout -q --detach FETCH_HEAD

    source_dir=$(realpath -e -- "${repository_dir}/${external_subdir:-.}")
    case "${source_dir}" in
        "${repository_dir}"|"${repository_dir}"/*) ;;
        *) die 'external tree is outside the external repository' ;;
    esac
    validate_external_tree "${source_dir}"
    external_paths=${source_dir}
elif [ -n "${external_ref}${external_subdir}" ]; then
    die 'BUILDROOT_EXTERNAL_REF and BUILDROOT_EXTERNAL_SUBDIR require BUILDROOT_EXTERNAL_URL'
fi

# Local trees override vendor defconfigs without changing the vendor repository
remaining=${BUILDROOT_EXTERNAL_PATHS:-}
external_index=0
while [ -n "${remaining}" ]; do
    external=${remaining%%:*}
    case "${remaining}" in
        *:*)
            remaining=${remaining#*:}
            [ -n "${remaining}" ] || die 'BUILDROOT_EXTERNAL_PATHS contains an empty path'
            ;;
        *) remaining= ;;
    esac
    validate_relative_path "${external}" 'external tree path'
    source_dir=$(realpath -e -- "${context_dir}/${external}")
    case "${source_dir}" in
        "${context_dir}"/*) ;;
        *) die "external tree is outside the build context: ${external}" ;;
    esac
    validate_external_tree "${source_dir}"

    destination="${external_root}/${external_index}"
    [ ! -e "${destination}" ] || die "external destination already exists: ${destination}"
    mkdir -p -- "$(dirname -- "${destination}")"
    cp -a --no-preserve=ownership -- "${source_dir}" "${destination}"
    external_paths=${external_paths:+${external_paths}:}${destination}
    external_index=$((external_index + 1))
done

export BR2_EXTERNAL="${external_paths}"
cd -- "${buildroot_dir}"

if [ -z "${BUILDROOT_CONFIG_FRAGMENTS:-}" ]; then
    exec make O="${output_dir}" BR2_EXTERNAL="${BR2_EXTERNAL}" "${BUILDROOT_DEFCONFIG}"
fi

# Match Buildroot's precedence for defconfigs from multiple external trees
base_config="${buildroot_dir}/configs/${BUILDROOT_DEFCONFIG}"
old_ifs=${IFS}
IFS=:
for external in ${external_paths}; do
    if [ -f "${external}/configs/${BUILDROOT_DEFCONFIG}" ]; then
        base_config="${external}/configs/${BUILDROOT_DEFCONFIG}"
    fi
done
IFS=${old_ifs}
[ -f "${base_config}" ] || die "Buildroot defconfig does not exist: ${BUILDROOT_DEFCONFIG}"

set -- "${base_config}"
for fragment in ${BUILDROOT_CONFIG_FRAGMENTS}; do
    validate_relative_path "${fragment}" 'Buildroot config fragment'
    fragment_path="${buildroot_dir}/${fragment}"
    if [ ! -f "${fragment_path}" ]; then
        fragment_path=
        IFS=:
        for external in ${external_paths}; do
            if [ -f "${external}/${fragment}" ]; then
                fragment_path="${external}/${fragment}"
            fi
        done
        IFS=${old_ifs}
    fi
    [ -n "${fragment_path}" ] && [ -f "${fragment_path}" ] || \
        die "Buildroot config fragment is not readable: ${fragment}"
    set -- "$@" "${fragment_path}"
done

CONFIG_='' ./support/kconfig/merge_config.sh \
    -m -e "${BR2_EXTERNAL}" -O "${output_dir}" "$@"
exec make O="${output_dir}" BR2_EXTERNAL="${BR2_EXTERNAL}" \
    KCONFIG_ALLCONFIG="${output_dir}/.config" alldefconfig
