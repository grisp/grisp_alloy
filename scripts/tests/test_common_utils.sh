#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

COMMON_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/common.sh"
# shellcheck source=scripts/utils/common.sh
source "${COMMON_UTILS_SCRIPT}"

common_utils_test_reset() {
    set +x
    unset ALLOY_TRACE || true
    ALLOY_DEBUG=0
    export ALLOY_DEBUG
    __ALLOY_HIDDEN_TRACE_STACK=()
}

test_common_utils_sources_debug_utilities() {
    common_utils_test_reset

    set_debug_level 2
    local debug_output
    debug_output="$(log_debug "common debug works" 2>&1)"

    assert_equals "2" "${ALLOY_DEBUG}"
    assert_matches "DEBUG: common debug works" "${debug_output}"
}

test_common_utils_fail_uses_exit_code_2_and_error_format() {
    local output status
    output="$(bash -c "source \"${COMMON_UTILS_SCRIPT}\"; fail boom" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "ERROR: boom" "${output}"
}

test_common_utils_require_var_accepts_set_values() {
    common_utils_test_reset
    export ALLOY_COMMON_TEST_VAR="ok"

    require_var ALLOY_COMMON_TEST_VAR
    assert_equals "ok" "${ALLOY_COMMON_TEST_VAR}"
}

test_common_utils_require_var_fails_for_missing_values() {
    local output status
    output="$(bash -c "source \"${COMMON_UTILS_SCRIPT}\"; unset MISSING_VAR; require_var MISSING_VAR" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Required variable is not set: MISSING_VAR" "${output}"
}

test_common_utils_source_required_utility_requires_argument() {
    local output status
    output="$({ source_required_utility; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "source_required_utility requires a utility path" "${output}"
}

test_common_utils_source_required_utility_loads_relative_script() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "common-utils")"
    mkdir -p "${temp_dir}/scripts/utils"
    cat > "${temp_dir}/scripts/utils/fixture.sh" <<'EOF'
fixture_loaded=true
fixture_func() { echo "fixture-ok"; }
EOF

    local original_root="${ALLOY_ROOT}"
    ALLOY_ROOT="${temp_dir}"
    source_required_utility "scripts/utils/fixture.sh"
    local result
    result="$(fixture_func)"
    ALLOY_ROOT="${original_root}"

    assert_equals "true" "${fixture_loaded:-}"
    assert_equals "fixture-ok" "${result}"
}

test_common_utils_source_required_utility_fails_for_missing_file() {
    local output status
    output="$({ source_required_utility "scripts/utils/does-not-exist.sh"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Missing required utility" "${output}"
}

test_common_utils_resolve_script_dir_resolves_symlinks() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "common-utils")"
    mkdir -p "${temp_dir}/src" "${temp_dir}/links"
    cat > "${temp_dir}/src/target.sh" <<'EOF'
#!/usr/bin/env bash
EOF
    ln -s "../src/target.sh" "${temp_dir}/links/alias.sh"

    local resolved
    resolved="$(resolve_script_dir "${temp_dir}/links/alias.sh")"

    assert_equals "${temp_dir}/src" "${resolved}"
}

test_common_utils_is_non_negative_integer_matches_expected_values() {
    assert_status_code 0 "bash -c 'source \"${COMMON_UTILS_SCRIPT}\"; is_non_negative_integer 0'"
    assert_status_code 0 "bash -c 'source \"${COMMON_UTILS_SCRIPT}\"; is_non_negative_integer 42'"
    assert_status_code 1 "bash -c 'source \"${COMMON_UTILS_SCRIPT}\"; is_non_negative_integer -1'"
    assert_status_code 1 "bash -c 'source \"${COMMON_UTILS_SCRIPT}\"; is_non_negative_integer nope'"
}

test_common_utils_require_command_reports_missing_binary() {
    local output status
    output="$({ require_command definitely-not-a-command; } 2>&1)"
    status=$?

    assert_equals "127" "${status}"
    assert_matches "Required command not found: definitely-not-a-command" "${output}"
}

test_common_utils_require_commands_requires_non_empty_argument_list() {
    local output status
    output="$(bash -c "source \"${COMMON_UTILS_SCRIPT}\"; require_commands" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "require_commands requires at least one command name" "${output}"
}

test_common_utils_print_helpers_emit_plain_output_by_default() {
    local result_out note_out hint_out
    result_out="$(print_result "build complete")"
    note_out="$(print_note "remember this")"
    hint_out="$(print_hint "try --help")"

    assert_equals "build complete" "${result_out}"
    assert_equals "remember this" "${note_out}"
    assert_equals "try --help" "${hint_out}"
}
