#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

NUGGETS_DIR="$(harness_repo_root)/nuggets"

test_builtin_nuggets_registry_lists_bootstrap_chain() {
    local registry_file="${NUGGETS_DIR}/.nuggets"
    local registry_contents
    registry_contents="$(cat "${registry_file}")"

    assert_status_code 0 "[[ -f '${registry_file}' ]]"
    assert_matches "builder_buildroot/builder_buildroot.nugget" "${registry_contents}"
    assert_matches "toolchain_smoke/toolchain_smoke.nugget" "${registry_contents}"
    assert_matches "platform_smoke/platform_smoke.nugget" "${registry_contents}"
    assert_matches "system_smoke/system_smoke.nugget" "${registry_contents}"
    assert_matches "bootflow_smoke/bootflow_smoke.nugget" "${registry_contents}"
    assert_matches "smoke_product/smoke_product.nugget" "${registry_contents}"
}

test_builtin_nuggets_sample_product_depends_on_bootstrap_backbone() {
    local product_file="${NUGGETS_DIR}/smoke_product/smoke_product.nugget"
    local system_file="${NUGGETS_DIR}/system_smoke/system_smoke.nugget"

    assert_status_code 0 "[[ -f '${product_file}' ]]"
    assert_status_code 0 "[[ -f '${system_file}' ]]"
    assert_status_code 0 "grep -Fq '{id, smoke_product}' '${product_file}'"
    assert_status_code 0 "grep -Fq '{required, nugget, builder_buildroot}' '${product_file}'"
    assert_status_code 0 "grep -Fq '{required, nugget, system_smoke}' '${product_file}'"
    assert_status_code 0 "grep -Fq '{required, nugget, toolchain_smoke}' '${system_file}'"
    assert_status_code 0 "grep -Fq '{required, nugget, platform_smoke}' '${system_file}'"
    assert_status_code 0 "grep -Fq '{required, nugget, bootflow_smoke}' '${system_file}'"
}

test_builtin_nuggets_bootstrap_platform_toolchain_and_bootflow_metadata_exist() {
    local builder_file="${NUGGETS_DIR}/builder_buildroot/builder_buildroot.nugget"
    local platform_file="${NUGGETS_DIR}/platform_smoke/platform_smoke.nugget"
    local toolchain_file="${NUGGETS_DIR}/toolchain_smoke/toolchain_smoke.nugget"
    local bootflow_file="${NUGGETS_DIR}/bootflow_smoke/bootflow_smoke.nugget"
    local platform_exports="${NUGGETS_DIR}/platform_smoke/scripts/exports.sh"

    assert_status_code 0 "grep -Fq '{buildroot_version, <<\"2025.05\">>}' '${builder_file}'"
    assert_status_code 0 "grep -Fq '{buildroot_url, {computed, <<\"https://buildroot.org/downloads/buildroot-[[ALLOY_CONFIG_BUILDROOT_VERSION]].tar.gz\">>}}' '${builder_file}'"
    assert_status_code 0 "grep -Fq '{buildroot_path, {computed, <<\"[[ALLOY_BUILD_DIR]]/buildroot\">>}}' '${builder_file}'"
    assert_status_code 0 "grep -Fq '{pre_build, <<\"scripts/pre-build.sh\">>, all}' '${builder_file}'"
    assert_status_code 1 "grep -Fq '{builder_backend, buildroot}' '${builder_file}'"
    assert_status_code 0 "grep -Fqx 'BR2_CCACHE=y' '${NUGGETS_DIR}/builder_buildroot/buildroot.defconfig.fragment'"
    assert_status_code 0 "grep -Fqx 'BR2_CCACHE_DIR=\"[[ALLOY_CACHE_DIR]]/buildroot/ccache\"' '${NUGGETS_DIR}/builder_buildroot/buildroot.defconfig.fragment'"
    assert_status_code 0 "[[ -x '${NUGGETS_DIR}/builder_buildroot/scripts/pre-build.sh' ]]"
    assert_status_code 0 "grep -Fq '{target_arch, {exec, <<\"scripts/exports.sh\">>}}' '${platform_file}'"
    assert_status_code 0 "grep -Fq '{target_arch_triplet, {exec, <<\"scripts/exports.sh\">>}}' '${platform_file}'"
    assert_status_code 0 "grep -Fq '{buildroot_arch_symbol, {exec, <<\"scripts/exports.sh\">>}}' '${platform_file}'"
    assert_status_code 0 "grep -Fq '{defconfig_fragment, <<\"buildroot.defconfig.fragment\">>}' '${platform_file}'"
    assert_status_code 0 "grep -Fq '{defconfig_fragment, <<\"buildroot.defconfig.fragment\">>}' '${toolchain_file}'"
    assert_status_code 0 "grep -Fq '{firmware_variant, [plain]}' '${bootflow_file}'"
    assert_status_code 0 "grep -Fqx 'BR2_[[ALLOY_CONFIG_BUILDROOT_ARCH_SYMBOL]]=y' '${NUGGETS_DIR}/platform_smoke/buildroot.defconfig.fragment'"
    assert_status_code 0 "grep -Fqx '[[ALLOY_CONFIG_BUILDROOT_CPU_FRAGMENT]]' '${NUGGETS_DIR}/platform_smoke/buildroot.defconfig.fragment'"
    assert_status_code 0 "[[ -x '${platform_exports}' ]]"
    assert_matches "^(x86_64|aarch64)-buildroot-linux-gnu$" "$("${platform_exports}" target_arch_triplet)"
    assert_status_code 0 "grep -Fqx 'BR2_TOOLCHAIN_BUILDROOT=y' '${NUGGETS_DIR}/toolchain_smoke/buildroot.defconfig.fragment'"
    assert_status_code 0 "grep -Fqx 'BR2_TOOLCHAIN_BUILDROOT_GLIBC=y' '${NUGGETS_DIR}/toolchain_smoke/buildroot.defconfig.fragment'"
    assert_status_code 0 "grep -Fqx 'BR2_TARGET_ROOTFS_TAR=y' '${NUGGETS_DIR}/system_smoke/buildroot.defconfig.fragment'"
}

test_builtin_nuggets_builder_pre_build_extracts_buildroot_and_links_download_cache() {
    harness_require_command tar

    local temp_dir source_dir tarball_path buildroot_path dl_target
    temp_dir="$(harness_make_temp_dir "builder-buildroot-hook")"
    source_dir="${temp_dir}/source/buildroot-2025.05"
    tarball_path="${temp_dir}/buildroot-2025.05.tar.gz"
    buildroot_path="${temp_dir}/build/buildroot"

    mkdir -p "${source_dir}"
    printf 'export BR2_VERSION := 2025.05\n' > "${source_dir}/Makefile"
    tar -C "${temp_dir}/source" -czf "${tarball_path}" buildroot-2025.05

    ALLOY_CACHE_DIR="${temp_dir}/cache" \
        ALLOY_CONFIG_BUILDROOT_PATH="${buildroot_path}" \
        ALLOY_CONFIG_BUILDROOT_VERSION="2025.05" \
        ALLOY_CONFIG_BUILDROOT_URL="file://${tarball_path}" \
        "${NUGGETS_DIR}/builder_buildroot/scripts/pre-build.sh" >/dev/null 2>&1

    assert_status_code 0 "[[ -f '${buildroot_path}/Makefile' ]]"
    assert_status_code 0 "[[ -f '${temp_dir}/cache/buildroot/buildroot-2025.05.tar.gz' ]]"
    assert_status_code 0 "[[ -d '${temp_dir}/cache/buildroot/downloads' ]]"
    assert_status_code 0 "[[ -d '${temp_dir}/cache/buildroot/ccache' ]]"
    assert_status_code 0 "[[ -L '${buildroot_path}/dl' ]]"

    dl_target="$(readlink "${buildroot_path}/dl")"
    assert_equals "${temp_dir}/cache/buildroot/downloads" "${dl_target}"
}
