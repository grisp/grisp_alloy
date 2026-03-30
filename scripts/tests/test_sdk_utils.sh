#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

SDK_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/sdk_utils.sh"
PREPARE_SDK_COMMAND="$(harness_repo_root)/scripts/commands/prepare-sdk.sh"
# shellcheck source=scripts/utils/sdk_utils.sh
source "${SDK_UTILS_SCRIPT}"

sdk_utils_test_make_sdk_root() {
    local temp_dir="$1"
    local sdk_dir="${temp_dir}/sdk"
    mkdir -p "${sdk_dir}/host" "${sdk_dir}/images" "${sdk_dir}/scripts"
    : > "${sdk_dir}/ALLOY_SDK_MANIFEST"
    printf 'prefix=%s/host\n' "${ALLOY_SDK_RELOCATION_PLACEHOLDER}" > "${sdk_dir}/scripts/tool.env"
    printf 'scripts/tool.env\n' > "${sdk_dir}/.alloy_relocation_manifest"
    printf '%s\n' "${ALLOY_SDK_RELOCATION_PLACEHOLDER}" > "${sdk_dir}/.alloy_sdk_dir"
    printf '%s\n' "${sdk_dir}"
}

sdk_utils_test_make_sdk_command_fixture() {
    local temp_dir="$1"
    local sdk_dir
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"
    mkdir -p "${sdk_dir}/scripts/utils" "${sdk_dir}/scripts/commands"

    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${sdk_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${sdk_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${sdk_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/file_utils.sh" "${sdk_dir}/scripts/utils/file_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/sdk_utils.sh" "${sdk_dir}/scripts/utils/sdk_utils.sh"
    cp "${PREPARE_SDK_COMMAND}" "${sdk_dir}/scripts/commands/prepare-sdk.sh"
    chmod +x "${sdk_dir}/scripts/commands/prepare-sdk.sh"

    printf '%s\n' "${sdk_dir}"
}

test_sdk_utils_check_sdk_relocation_detects_placeholder_state() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"

    local output status
    output="$({ check_sdk_relocation "${sdk_dir}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_equals "" "${output}"
}

test_sdk_utils_relocate_sdk_rewrites_placeholder_and_updates_state() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"

    relocate_sdk "${sdk_dir}"

    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
    assert_equals "${sdk_dir}" "$(cat "${sdk_dir}/.alloy_sdk_dir")"
    assert_status_code 0 "check_sdk_relocation '${sdk_dir}'"
}

test_sdk_utils_relocate_sdk_rewrites_stale_sdk_path() {
    local temp_dir sdk_dir old_root
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"
    old_root="/opt/grisp/sdk-old"
    printf 'prefix=%s/host\n' "${old_root}" > "${sdk_dir}/scripts/tool.env"
    printf '%s\n' "${old_root}" > "${sdk_dir}/.alloy_sdk_dir"

    relocate_sdk "${sdk_dir}"

    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
    assert_equals "${sdk_dir}" "$(cat "${sdk_dir}/.alloy_sdk_dir")"
}

test_sdk_utils_ensure_sdk_relocated_fails_when_sdk_root_is_not_writable() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"
    chmod 0555 "${sdk_dir}"

    local output status
    output="$({ ensure_sdk_relocated "${sdk_dir}"; } 2>&1)"
    status=$?

    chmod 0755 "${sdk_dir}"

    assert_equals "1" "${status}"
    assert_matches "SDK needs relocation but the SDK directory is not writable" "${output}"
    assert_matches "Run: alloy prepare sdk" "${output}"
}

test_sdk_utils_ensure_sdk_relocated_auto_relocates_writable_sdk() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"

    local output
    output="$(ensure_sdk_relocated "${sdk_dir}")"

    assert_matches "Relocating SDK to ${sdk_dir}" "${output}"
    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
}

test_sdk_utils_prepare_sdk_command_relocates_sdk_fixture() {
    local temp_dir sdk_dir command_path
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_command_fixture "${temp_dir}")"
    command_path="${sdk_dir}/scripts/commands/prepare-sdk.sh"

    local output status
    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR "${command_path}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Relocating SDK to ${sdk_dir}" "${output}"
    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
    assert_equals "${sdk_dir}" "$(cat "${sdk_dir}/.alloy_sdk_dir")"
}

test_sdk_utils_prepare_sdk_command_reports_already_relocated_sdk() {
    local temp_dir sdk_dir command_path
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_command_fixture "${temp_dir}")"
    printf 'prefix=%s/host\n' "${sdk_dir}" > "${sdk_dir}/scripts/tool.env"
    printf '%s\n' "${sdk_dir}" > "${sdk_dir}/.alloy_sdk_dir"
    command_path="${sdk_dir}/scripts/commands/prepare-sdk.sh"

    local output status
    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR "${command_path}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "SDK is already relocated." "${output}"
}

test_sdk_utils_prepare_sdk_command_rejects_repository_mode() {
    local output status
    output="$("${PREPARE_SDK_COMMAND}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "prepare sdk is only available in sdk mode" "${output}"
}

test_sdk_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${SDK_UTILS_SCRIPT}\"; source \"${SDK_UTILS_SCRIPT}\"; type ensure_sdk_relocated >/dev/null'"
}
