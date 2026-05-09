#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

DEBUG_TOOLS_SCRIPT="$(harness_repo_root)/scripts/utils/debug_tools.sh"

# shellcheck source=scripts/utils/debug_tools.sh
source "${DEBUG_TOOLS_SCRIPT}"

test_debug_tools_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${DEBUG_TOOLS_SCRIPT}\"; source \"${DEBUG_TOOLS_SCRIPT}\"; type alloy_log_info >/dev/null'"
}

test_debug_tools_log_levels_and_prefixes() {
    local output
    output="$(ALLOY_HOOK_TYPE=pre_build ALLOY_NUGGET=builder_buildroot ALLOY_DEBUG=2 bash -c '
        source "'"${DEBUG_TOOLS_SCRIPT}"'";
        alloy_log_info "info message";
        alloy_log_debug "debug message";
        alloy_log_warn "warn message";
        alloy_log_error "error message";
    ' 2>&1)"

    assert_matches "\\[pre_build:builder_buildroot\\] INFO: info message" "${output}"
    assert_matches "\\[pre_build:builder_buildroot\\] DEBUG: debug message" "${output}"
    assert_matches "\\[pre_build:builder_buildroot\\] WARN: warn message" "${output}"
    assert_matches "\\[pre_build:builder_buildroot\\] ERROR: error message" "${output}"
}

test_debug_tools_info_hidden_when_debug_below_one() {
    local output
    output="$(ALLOY_HOOK_TYPE=post_build ALLOY_NUGGET=core ALLOY_DEBUG=0 bash -c '
        source "'"${DEBUG_TOOLS_SCRIPT}"'";
        alloy_log_info "hidden";
        alloy_log_warn "shown";
    ' 2>&1)"

    assert_equals "[post_build:core] WARN: shown" "${output}"
}

test_debug_tools_alloy_log_format_path_prefers_root_relative_then_absolute() {
    local temp_dir root_dir outside inside formatted_inside formatted_outside
    temp_dir="$(harness_make_temp_dir "debug-tools-path")"
    root_dir="${temp_dir}/repo"
    inside="${root_dir}/nuggets/core/file.txt"
    outside="${temp_dir}/outside/file.txt"
    mkdir -p "$(dirname "${inside}")" "$(dirname "${outside}")"
    : > "${inside}"
    : > "${outside}"

    formatted_inside="$(ALLOY_ROOT_DIR="${root_dir}" ALLOY_HOOK_TYPE=pre_build ALLOY_NUGGET=core bash -c '
        source "'"${DEBUG_TOOLS_SCRIPT}"'";
        alloy_log_format_path "'"${inside}"'";
    ')"
    formatted_outside="$(ALLOY_ROOT_DIR="${root_dir}" ALLOY_HOOK_TYPE=pre_build ALLOY_NUGGET=core bash -c '
        source "'"${DEBUG_TOOLS_SCRIPT}"'";
        alloy_log_format_path "'"${outside}"'";
    ')"

    assert_equals "nuggets/core/file.txt" "${formatted_inside}"
    assert_equals "${outside}" "${formatted_outside}"
}

test_debug_tools_honors_explicit_alloy_log_prefix() {
    local output
    output="$(ALLOY_LOG_PREFIX='alloy:post_build:core' ALLOY_DEBUG=1 bash -c '
        source "'"${DEBUG_TOOLS_SCRIPT}"'";
        alloy_log_info "prefixed";
    ' 2>&1)"

    assert_equals "[alloy:post_build:core] INFO: prefixed" "${output}"
}
