#!/usr/bin/env bash

set -euo pipefail

readonly REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
readonly MANIFEST_TOOL="${REPO_ROOT}/scripts/release-manifest.sh"
readonly TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

make_machine() {
    local machine_dir="$1"
    local asset_prefix="$2"
    local machine_root="${TEST_ROOT}/repo/${machine_dir}"

    mkdir -p -- "${machine_root}"
    printf 'variable "BUILD_REVISION" { default = "1" }\n' \
        > "${machine_root}/build.hcl"
    printf 'RELEASE_ASSET_PREFIX=%s\n' "${asset_prefix}" \
        > "${machine_root}/machine.conf"
    printf '#!/usr/bin/env bash\n' > "${machine_root}/run.sh"
    chmod +x "${machine_root}/run.sh"

    printf '%s\n' "${asset_prefix}" > \
        "${TEST_ROOT}/dist/${asset_prefix}-v1.2.3.tar.zst"
    (
        cd -- "${TEST_ROOT}/dist"
        sha256sum "${asset_prefix}-v1.2.3.tar.zst" > \
            "${asset_prefix}-v1.2.3.tar.zst.sha256"
    )
}

mkdir -p -- "${TEST_ROOT}/repo/machine" "${TEST_ROOT}/dist"
make_machine machine/arm/board-a arm-board-a
make_machine machine/riscv64/board-b riscv64-board-b

readonly SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly MANIFEST="${TEST_ROOT}/dist/qemu-machine-images-v1.2.3.json"
readonly SECOND_MANIFEST="${TEST_ROOT}/dist/second-manifest.json"
readonly ASSETS="${TEST_ROOT}/assets.json"

"${MANIFEST_TOOL}" create \
    "${TEST_ROOT}/repo" \
    v1.2.3 \
    "${TEST_ROOT}/dist" \
    "${SOURCE_SHA}" \
    "${MANIFEST}"
"${MANIFEST_TOOL}" validate v1.2.3 "${MANIFEST}"
"${MANIFEST_TOOL}" verify \
    "${TEST_ROOT}/repo" \
    v1.2.3 \
    "${MANIFEST}" \
    "${TEST_ROOT}/dist"
"${MANIFEST_TOOL}" create \
    "${TEST_ROOT}/repo" \
    v1.2.3 \
    "${TEST_ROOT}/dist" \
    "${SOURCE_SHA}" \
    "${SECOND_MANIFEST}"
cmp "${MANIFEST}" "${SECOND_MANIFEST}"

[[ "$(jq --raw-output '.schema' "${MANIFEST}")" == 1 ]]
[[ "$(jq --raw-output '.machines | length' "${MANIFEST}")" == 2 ]]
[[ "$(jq --raw-output \
    '.machines["machine/arm/board-a"].built_from' \
    "${MANIFEST}")" == "${SOURCE_SHA}" ]]

jq '[.machines[].asset] + ([.machines[].asset] | map(. + ".sha256"))' \
    "${MANIFEST}" > "${ASSETS}"
[[ "$("${MANIFEST_TOOL}" select \
    "${TEST_ROOT}/repo" v1.2.3 "${MANIFEST}" "${ASSETS}" auto)" == '[]' ]]
[[ "$("${MANIFEST_TOOL}" select \
    "${TEST_ROOT}/repo" v1.2.3 - - auto)" == \
    '["machine/arm/board-a","machine/riscv64/board-b"]' ]]
[[ "$("${MANIFEST_TOOL}" select \
    "${TEST_ROOT}/repo" v1.2.3 "${MANIFEST}" "${ASSETS}" \
    machine/riscv64/board-b)" == '["machine/riscv64/board-b"]' ]]
if "${MANIFEST_TOOL}" select \
    "${TEST_ROOT}/repo" v1.2.3 "${MANIFEST}" "${ASSETS}" \
    machine/arm/unknown >/dev/null 2>&1; then
    echo "unknown machine selection was accepted" >&2
    exit 1
fi

jq '.schema = 2' "${MANIFEST}" > "${TEST_ROOT}/invalid.json"
if "${MANIFEST_TOOL}" validate \
    v1.2.3 "${TEST_ROOT}/invalid.json" >/dev/null 2>&1; then
    echo "invalid manifest was accepted" >&2
    exit 1
fi

printf 'changed\n' >> \
    "${TEST_ROOT}/repo/machine/arm/board-a/build.hcl"
[[ "$("${MANIFEST_TOOL}" select \
    "${TEST_ROOT}/repo" v1.2.3 "${MANIFEST}" "${ASSETS}" auto)" == \
    '["machine/arm/board-a"]' ]]
if "${MANIFEST_TOOL}" verify \
    "${TEST_ROOT}/repo" \
    v1.2.3 \
    "${MANIFEST}" \
    "${TEST_ROOT}/dist" >/dev/null 2>&1; then
    echo "stale build specification was accepted" >&2
    exit 1
fi
printf 'variable "BUILD_REVISION" { default = "1" }\n' \
    > "${TEST_ROOT}/repo/machine/arm/board-a/build.hcl"

jq 'map(select(. != "riscv64-board-b-v1.2.3.tar.zst.sha256"))' \
    "${ASSETS}" > "${TEST_ROOT}/incomplete-assets.json"
[[ "$("${MANIFEST_TOOL}" select \
    "${TEST_ROOT}/repo" \
    v1.2.3 \
    "${MANIFEST}" \
    "${TEST_ROOT}/incomplete-assets.json" \
    auto)" == '["machine/riscv64/board-b"]' ]]

printf 'corrupt\n' > "${TEST_ROOT}/dist/arm-board-a-v1.2.3.tar.zst"
if "${MANIFEST_TOOL}" verify \
    "${TEST_ROOT}/repo" \
    v1.2.3 \
    "${MANIFEST}" \
    "${TEST_ROOT}/dist" >/dev/null 2>&1; then
    echo "corrupt archive was accepted" >&2
    exit 1
fi
