#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

BUILD_SDK_COMMAND="$(harness_repo_root)/scripts/commands/build-sdk.sh"

build_sdk_test_make_fixture() {
    local temp_dir="$1"
    local root_dir="${temp_dir}/fixture"
    mkdir -p "${root_dir}/scripts/commands" "${root_dir}/scripts/utils" "${root_dir}/scripts/tests/lib"
    cp "${BUILD_SDK_COMMAND}" "${root_dir}/scripts/commands/build-sdk.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${root_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${root_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${root_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/argparse.sh" "${root_dir}/scripts/argparse.sh"
    chmod +x "${root_dir}/scripts/commands/build-sdk.sh"
    printf '%s\n' "${root_dir}"
}

test_build_sdk_command_help_shows_canonical_usage() {
    local output status

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR \
        "${BUILD_SDK_COMMAND}" --help 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Usage: alloy build sdk PRODUCT_NUGGET \\[OPTIONS\\]" "${output}"
    assert_matches "--clean-package PKG" "${output}"
    assert_status_code 1 "printf '%s\n' '${output}' | grep -F -- '-c PKG'"
}

test_build_sdk_command_requires_product_nugget() {
    local output status

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR \
        "${BUILD_SDK_COMMAND}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Missing PRODUCT_NUGGET" "${output}"
}

test_build_sdk_command_rejects_sdk_mode() {
    local output status

    output="$(ALLOY_MODE=sdk "${BUILD_SDK_COMMAND}" demo 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "build sdk is only available in repository mode" "${output}"
}

test_build_sdk_command_direct_invocation_infers_sdk_mode_from_manifest_and_rejects_it() {
    local temp_dir root_dir command_path output status
    temp_dir="$(harness_make_temp_dir "build-sdk-sdk-mode")"
    root_dir="$(build_sdk_test_make_fixture "${temp_dir}")"
    command_path="${root_dir}/scripts/commands/build-sdk.sh"
    : > "${root_dir}/ALLOY_SDK_MANIFEST"

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR -u ALLOY_ARTEFACT_DIR -u ALLOY_CACHE_DIR \
        "${command_path}" demo 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "build sdk is only available in repository mode" "${output}"
}

test_build_sdk_command_creates_expected_layout_and_reports_sources() {
    local temp_dir build_root output status
    temp_dir="$(harness_make_temp_dir "build-sdk-layout")"
    build_root="${temp_dir}/build"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_NUGGET_PATH="env_one:env_two" \
        "${BUILD_SDK_COMMAND}" demo_product \
        -n local_one \
        -n git+https://example.com/nuggets.git#v1 \
        --include-sources \
        --allow-dirty 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/plan' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/targets' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/staging' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/motherlode' ]]"
    assert_matches "Initialized SDK build workspace for demo_product" "${output}"
    assert_matches "Additional command-line nugget sources: 2" "${output}"
    assert_matches "Additional environment nugget sources: 2" "${output}"
    assert_matches "Dirty VCS checkouts are allowed" "${output}"
    assert_matches "Legal-info source export was requested" "${output}"
}

test_build_sdk_command_clean_removes_existing_workspace() {
    local temp_dir build_root workspace output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean")"
    build_root="${temp_dir}/build"
    workspace="${build_root}/sdk/demo_product"
    mkdir -p "${workspace}"
    printf 'stale\n' > "${workspace}/stale.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -c 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 1 "[[ -e '${workspace}/stale.txt' ]]"
    assert_status_code 0 "[[ -d '${workspace}/plan' ]]"
    assert_matches "Initialized SDK build workspace for demo_product" "${output}"
}

test_build_sdk_command_short_c_with_value_is_rejected_as_extra_positional() {
    local temp_dir build_root workspace output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean-package")"
    build_root="${temp_dir}/build"
    workspace="${build_root}/sdk/demo_product"
    mkdir -p "${workspace}"
    printf 'keep\n' > "${workspace}/stale.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -c busybox 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_status_code 0 "[[ -e '${workspace}/stale.txt' ]]"
    assert_matches "Unexpected positional arguments: busybox" "${output}"
}

test_build_sdk_command_long_clean_package_is_supported() {
    local temp_dir build_root output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean-package-long")"
    build_root="${temp_dir}/build"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product --clean-package busybox 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Queued clean-package requests: busybox" "${output}"
}

test_build_sdk_command_rejects_invalid_allow_dirty_env_value() {
    local output status

    output="$(ALLOY_ALLOW_DIRTY=maybe \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "ALLOY_ALLOW_DIRTY must be true or false" "${output}"
}
