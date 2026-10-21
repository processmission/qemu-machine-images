#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )); then
    echo "usage: $0 BUILDROOT_SOURCE_DIR" >&2
    exit 2
fi

BUILDROOT_DIR="$(realpath -e -- "$1")"
readonly BUILDROOT_DIR
REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
readonly REPO_ROOT
readonly CONFIGURE_TOOL="${REPO_ROOT}/scripts/configure-buildroot.sh"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
cleanup() {
    local result=$?
    if (( result != 0 )); then
        find "${TEST_ROOT}" -name '*.log' -exec tail -n 20 {} + >&2
    fi
    rm -rf -- "${TEST_ROOT}"
    exit "${result}"
}
trap cleanup EXIT

make_external_tree() {
    local tree_dir="$1"
    local tree_name="$2"
    local hostname="$3"
    mkdir -p "${tree_dir}/configs"
    printf 'name: %s\n' "${tree_name}" > "${tree_dir}/external.desc"
    printf 'config BR2_EXTERNAL_TEST_%s\n\tbool "External test"\n' \
        "${tree_name}" > "${tree_dir}/Config.in"
    printf 'EXTERNAL_TEST_ORDER += %s\n' "${tree_name}" > "${tree_dir}/external.mk"
    printf 'BR2_riscv=y\nBR2_TARGET_GENERIC_HOSTNAME="%s"\nBR2_EXTERNAL_TEST_%s=y\n' \
        "${hostname}" "${tree_name}" > "${tree_dir}/configs/external_test_defconfig"
}

mkdir -p "${TEST_ROOT}/context"
for tree in FIRST SECOND; do
    make_external_tree "${TEST_ROOT}/context/${tree}" "${tree}" "${tree}"
done
printf 'BR2_TARGET_GENERIC_HOSTNAME="fragment"\n' > \
    "${TEST_ROOT}/context/SECOND/configs/hostname.fragment"

vendor_dir="${TEST_ROOT}/vendor"
make_external_tree "${vendor_dir}" VENDOR PINNED
make_external_tree "${vendor_dir}/br2-external" VENDOR_BOARD SUBDIR_PINNED
mkdir -p "${vendor_dir}/shared" "${vendor_dir}/incomplete"
printf 'remote-sibling\n' > "${vendor_dir}/shared/marker"
printf 'name: INCOMPLETE\n' > "${vendor_dir}/incomplete/external.desc"
printf 'BR2_TARGET_GENERIC_HOSTNAME="remote-fragment"\n' > \
    "${vendor_dir}/br2-external/configs/remote.fragment"
cat >> "${vendor_dir}/br2-external/external.mk" <<'EOF'
REMOTE_SIBLING_MARKER = $(shell cat $(BR2_EXTERNAL_VENDOR_BOARD_PATH)/../shared/marker)
EOF
ln -s "${TEST_ROOT}/context/FIRST" "${vendor_dir}/outside"
git -C "${vendor_dir}" init --quiet --initial-branch=main
git -C "${vendor_dir}" config user.name 'External tree test'
git -C "${vendor_dir}" config user.email external-test@example.com
git -C "${vendor_dir}" config commit.gpgsign false
git -C "${vendor_dir}" config core.hooksPath /dev/null
git -C "${vendor_dir}" add --all
git -C "${vendor_dir}" commit --quiet \
    --message 'test: record vendor external trees' \
    --message 'Provide pinned source fixtures for external tree integration.'
vendor_revision="$(git -C "${vendor_dir}" rev-parse HEAD)"
git -C "${vendor_dir}" tag vendor-v1 "${vendor_revision}"
sed -i 's/PINNED/HEAD/' "${vendor_dir}/configs/external_test_defconfig" \
    "${vendor_dir}/br2-external/configs/external_test_defconfig"
git -C "${vendor_dir}" add --all
git -C "${vendor_dir}" commit --quiet \
    --message 'test: advance the vendor branch' \
    --message 'Ensure explicit revisions take precedence over the branch head.'
vendor_url="file://${vendor_dir}"

configure() {
    local case_name="$1"
    shift
    mkdir -p "${TEST_ROOT}/${case_name}"
    env BR2_EXTERNAL= BUILDROOT_EXTERNAL_PATHS= BUILDROOT_CONFIG_FRAGMENTS= \
        BUILDROOT_EXTERNAL_URL= BUILDROOT_EXTERNAL_REF= BUILDROOT_EXTERNAL_SUBDIR= \
        "$@" "${CONFIGURE_TOOL}" "${BUILDROOT_DIR}" \
        "${TEST_ROOT}/${case_name}/output" "${TEST_ROOT}/context" \
        > "${TEST_ROOT}/${case_name}/configure.log" 2>&1
}

# Exercise actual Kconfig parsing, external precedence, and makefile inclusion
configure multiple BUILDROOT_EXTERNAL_PATHS=FIRST:SECOND \
    BUILDROOT_DEFCONFIG=external_test_defconfig BUILDROOT_CONFIG_FRAGMENTS=
grep -qx 'BR2_TARGET_GENERIC_HOSTNAME="SECOND"' \
    "${TEST_ROOT}/multiple/output/.config"
grep -qx 'BR2_EXTERNAL_TEST_SECOND=y' "${TEST_ROOT}/multiple/output/.config"
test -f "${TEST_ROOT}/multiple/external/0/external.desc"
test -f "${TEST_ROOT}/multiple/external/1/external.desc"

# A later invocation must work after the original Docker context is unavailable
mv "${TEST_ROOT}/context" "${TEST_ROOT}/context.saved"
env -u BR2_EXTERNAL make --no-print-directory -s -C "${BUILDROOT_DIR}" \
    O="${TEST_ROOT}/multiple/output" olddefconfig \
    > "${TEST_ROOT}/multiple/persist.log" 2>&1
order="$(env -u BR2_EXTERNAL make --no-print-directory -s -C "${BUILDROOT_DIR}" \
    O="${TEST_ROOT}/multiple/output" printvars VARS=EXTERNAL_TEST_ORDER)"
[[ "${order}" == 'EXTERNAL_TEST_ORDER=FIRST SECOND' ]]
mv "${TEST_ROOT}/context.saved" "${TEST_ROOT}/context"

configure fragment BUILDROOT_EXTERNAL_PATHS=FIRST:SECOND \
    BUILDROOT_DEFCONFIG=external_test_defconfig \
    BUILDROOT_CONFIG_FRAGMENTS=configs/hostname.fragment
grep -qx 'BR2_TARGET_GENERIC_HOSTNAME="fragment"' \
    "${TEST_ROOT}/fragment/output/.config"
grep -qx 'BR2_EXTERNAL_TEST_SECOND=y' "${TEST_ROOT}/fragment/output/.config"

# Keep the original in-tree defconfig path working without an external tree
configure native BUILDROOT_EXTERNAL_PATHS= BUILDROOT_CONFIG_FRAGMENTS= \
    BUILDROOT_DEFCONFIG=qemu_riscv64_virt_defconfig
grep -qx 'BR2_riscv=y' "${TEST_ROOT}/native/output/.config"

# Fetch the requested revision rather than the repository's current branch
configure remote BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}" \
    BUILDROOT_DEFCONFIG=external_test_defconfig
grep -qx 'BR2_TARGET_GENERIC_HOSTNAME="PINNED"' \
    "${TEST_ROOT}/remote/output/.config"
[[ "$(git -C "${TEST_ROOT}/remote/external/remote" rev-parse HEAD)" == \
    "${vendor_revision}" ]]
mv "${vendor_dir}" "${vendor_dir}.saved"
env -u BR2_EXTERNAL make --no-print-directory -s -C "${BUILDROOT_DIR}" \
    O="${TEST_ROOT}/remote/output" olddefconfig \
    > "${TEST_ROOT}/remote/persist.log" 2>&1
grep -qx 'BR2_TARGET_GENERIC_HOSTNAME="PINNED"' \
    "${TEST_ROOT}/remote/output/.config"
mv "${vendor_dir}.saved" "${vendor_dir}"

# Preserve sibling files when the external tree is inside a vendor repository
configure remote-subdir BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF=vendor-v1 BUILDROOT_EXTERNAL_SUBDIR=br2-external \
    BUILDROOT_DEFCONFIG=external_test_defconfig
grep -qx 'BR2_TARGET_GENERIC_HOSTNAME="SUBDIR_PINNED"' \
    "${TEST_ROOT}/remote-subdir/output/.config"
marker="$(env -u BR2_EXTERNAL make --no-print-directory -s -C "${BUILDROOT_DIR}" \
    O="${TEST_ROOT}/remote-subdir/output" printvars VARS=REMOTE_SIBLING_MARKER)"
[[ "${marker}" == 'REMOTE_SIBLING_MARKER=remote-sibling' ]]

configure remote-fragment BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}" BUILDROOT_EXTERNAL_SUBDIR=br2-external \
    BUILDROOT_DEFCONFIG=external_test_defconfig \
    BUILDROOT_CONFIG_FRAGMENTS=configs/remote.fragment
grep -qx 'BR2_TARGET_GENERIC_HOSTNAME="remote-fragment"' \
    "${TEST_ROOT}/remote-fragment/output/.config"

# Apply local machine overrides after the vendor's base tree
configure mixed BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}" BUILDROOT_EXTERNAL_PATHS=FIRST:SECOND \
    BUILDROOT_DEFCONFIG=external_test_defconfig
grep -qx 'BR2_TARGET_GENERIC_HOSTNAME="SECOND"' "${TEST_ROOT}/mixed/output/.config"
order="$(env -u BR2_EXTERNAL make --no-print-directory -s -C "${BUILDROOT_DIR}" \
    O="${TEST_ROOT}/mixed/output" printvars VARS=EXTERNAL_TEST_ORDER)"
[[ "${order}" == 'EXTERNAL_TEST_ORDER=VENDOR FIRST SECOND' ]]

expect_failure() {
    local case_name="$1"
    shift
    if configure "${case_name}" BUILDROOT_DEFCONFIG=external_test_defconfig \
        BUILDROOT_CONFIG_FRAGMENTS= "$@"; then
        echo "invalid configuration was accepted: ${case_name}" >&2
        exit 1
    fi
}

expect_failure traversal BUILDROOT_EXTERNAL_PATHS=../context/FIRST
expect_failure absolute BUILDROOT_EXTERNAL_PATHS="${TEST_ROOT}/context/FIRST"
expect_failure empty-first BUILDROOT_EXTERNAL_PATHS=:FIRST
expect_failure empty-last BUILDROOT_EXTERNAL_PATHS=FIRST:
expect_failure empty-middle BUILDROOT_EXTERNAL_PATHS=FIRST::SECOND
mkdir -p "${TEST_ROOT}/outside"
ln -s "${TEST_ROOT}/outside" "${TEST_ROOT}/context/outside"
expect_failure symlink BUILDROOT_EXTERNAL_PATHS=outside
mkdir -p "${TEST_ROOT}/context/incomplete"
printf 'name: INCOMPLETE\n' > "${TEST_ROOT}/context/incomplete/external.desc"
expect_failure metadata BUILDROOT_EXTERNAL_PATHS=incomplete
expect_failure missing-fragment BUILDROOT_EXTERNAL_PATHS=FIRST \
    BUILDROOT_CONFIG_FRAGMENTS=configs/missing.fragment
expect_failure missing-revision BUILDROOT_EXTERNAL_URL="${vendor_url}"
expect_failure missing-url BUILDROOT_EXTERNAL_REF="${vendor_revision}"
expect_failure subdir-without-url BUILDROOT_EXTERNAL_SUBDIR=br2-external
expect_failure invalid-url BUILDROOT_EXTERNAL_URL=file:///nonexistent-external-test \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}"
expect_failure invalid-revision BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF=missing-branch
expect_failure option-revision BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF=--all
expect_failure remote-traversal BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}" BUILDROOT_EXTERNAL_SUBDIR=../context/FIRST
expect_failure remote-absolute BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}" BUILDROOT_EXTERNAL_SUBDIR="${vendor_dir}"
expect_failure remote-symlink BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}" BUILDROOT_EXTERNAL_SUBDIR=outside
expect_failure remote-metadata BUILDROOT_EXTERNAL_URL="${vendor_url}" \
    BUILDROOT_EXTERNAL_REF="${vendor_revision}" BUILDROOT_EXTERNAL_SUBDIR=incomplete

echo 'Buildroot external integration tests passed'
