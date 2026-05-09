#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

DEBUG_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/debug_utils.sh"
# shellcheck source=scripts/utils/debug_utils.sh
source "${DEBUG_UTILS_SCRIPT}"

debug_utils_test_reset() {
    set +x
    unset ALLOY_TRACE || true
    unset NO_COLOR || true
    ALLOY_DEBUG=0
    export ALLOY_DEBUG
    __ALLOY_HIDDEN_TRACE_STACK=()
}

test_debug_utils_set_debug_level_exports_value() {
    debug_utils_test_reset

    set_debug_level 2

    assert_equals "2" "${ALLOY_DEBUG}"
}

test_debug_utils_set_debug_level_rejects_invalid_values() {
    debug_utils_test_reset

    local output status
    output="$({ set_debug_level nope; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Invalid debug level" "${output}"
}

test_debug_utils_log_level_filtering() {
    debug_utils_test_reset

    local info0 debug0 warn0 error0
    info0="$(log_info "hello" 2>&1)"
    debug0="$(log_debug "hello" 2>&1)"
    warn0="$(log_warn "warn" 2>&1)"
    error0="$(log_error "err" 2>&1)"

    assert_equals "" "${info0}"
    assert_equals "" "${debug0}"
    assert_matches "WARN: warn" "${warn0}"
    assert_matches "ERROR: err" "${error0}"

    set_debug_level 2
    local info2 debug2
    info2="$(log_info "hello" 2>&1)"
    debug2="$(log_debug "hello" 2>&1)"
    assert_matches "INFO: hello" "${info2}"
    assert_matches "DEBUG: hello" "${debug2}"
}

test_debug_utils_log_output_uses_ansi_colors_when_supported() {
    debug_utils_test_reset
    set_debug_level 2

    local original_supports_color
    original_supports_color="$(declare -f console_supports_color)"
    console_supports_color() { return 0; }

    local info_out warn_out error_out debug_out
    info_out="$(log_info "hello" 2>&1)"
    warn_out="$(log_warn "warn" 2>&1)"
    error_out="$(log_error "err" 2>&1)"
    debug_out="$(log_debug "dbg" 2>&1)"

    eval "${original_supports_color}"

    assert_equals $'\033[36mINFO: hello\033[0m' "${info_out}"
    assert_equals $'\033[33mWARN: warn\033[0m' "${warn_out}"
    assert_equals $'\033[31mERROR: err\033[0m' "${error_out}"
    assert_equals $'\033[90mDEBUG: dbg\033[0m' "${debug_out}"
}

test_debug_utils_no_color_disables_colored_logs() {
    debug_utils_test_reset
    set_debug_level 2

    local original_supports_color
    original_supports_color="$(declare -f console_supports_color)"
    console_supports_color() { [[ -z "${NO_COLOR:-}" ]]; }
    export NO_COLOR=1

    local warn_out
    warn_out="$(log_warn "warn" 2>&1)"

    unset NO_COLOR || true
    eval "${original_supports_color}"

    assert_equals "WARN: warn" "${warn_out}"
}

test_debug_utils_honors_explicit_alloy_log_prefix() {
    debug_utils_test_reset
    set_debug_level 2
    export ALLOY_LOG_PREFIX="alloy"

    local info_out
    info_out="$(log_info "hello" 2>&1)"
    unset ALLOY_LOG_PREFIX || true

    assert_equals "[alloy] INFO: hello" "${info_out}"
}

test_debug_utils_set_trace_toggles_xtrace_and_env() {
    debug_utils_test_reset

    local trace_file
    trace_file="$(harness_make_temp_file "grisp-alloy-xtrace")"
    local previous_xtracefd="${BASH_XTRACEFD-}"
    exec {xtrace_fd}> "${trace_file}"
    BASH_XTRACEFD="${xtrace_fd}"

    set_trace true
    local trace_on="false"
    if [[ "$-" == *x* ]]; then
        trace_on="true"
    fi
    : TRACE_TOGGLE_MARKER

    set_trace false
    local trace_off="false"
    if [[ "$-" != *x* ]]; then
        trace_off="true"
    fi
    exec {xtrace_fd}>&-
    if [[ -n "${previous_xtracefd}" ]]; then
        BASH_XTRACEFD="${previous_xtracefd}"
    else
        unset BASH_XTRACEFD || true
    fi

    assert_equals "true" "${trace_on}"
    assert_equals "true" "${trace_off}"
    assert_equals "" "${ALLOY_TRACE:-}"
    assert_status_code 0 "grep -Fq 'TRACE_TOGGLE_MARKER' '${trace_file}'"
    rm -f "${trace_file}"
}

test_debug_utils_hidden_sections_restore_trace_state() {
    debug_utils_test_reset

    local trace_file
    trace_file="$(harness_make_temp_file "grisp-alloy-xtrace")"
    local previous_xtracefd="${BASH_XTRACEFD-}"
    exec {xtrace_fd}> "${trace_file}"
    BASH_XTRACEFD="${xtrace_fd}"

    set_trace true
    : TRACE_BEFORE_HIDDEN
    enter_hidden
    local hidden_off="false"
    if [[ "$-" != *x* ]]; then
        hidden_off="true"
    fi
    : TRACE_INSIDE_HIDDEN

    leave_hidden
    : TRACE_AFTER_HIDDEN
    local restored_on="false"
    if [[ "$-" == *x* ]]; then
        restored_on="true"
    fi

    set_trace false
    exec {xtrace_fd}>&-
    if [[ -n "${previous_xtracefd}" ]]; then
        BASH_XTRACEFD="${previous_xtracefd}"
    else
        unset BASH_XTRACEFD || true
    fi

    assert_equals "true" "${hidden_off}"
    assert_equals "true" "${restored_on}"
    assert_status_code 0 "grep -Fq 'TRACE_BEFORE_HIDDEN' '${trace_file}'"
    assert_status_code 0 "grep -Fq 'TRACE_AFTER_HIDDEN' '${trace_file}'"
    assert_status_code 1 "grep -Fq 'TRACE_INSIDE_HIDDEN' '${trace_file}'"
    rm -f "${trace_file}"
}

test_debug_utils_die_supports_default_and_custom_exit_codes() {
    local script="${DEBUG_UTILS_SCRIPT}"

    assert_status_code 1 "bash -c 'source \"${script}\"; die boom'"
    assert_status_code 7 "bash -c 'source \"${script}\"; die 7 boom'"
}

test_debug_utils_sourcing_applies_trace_from_environment() {
    local script="${DEBUG_UTILS_SCRIPT}"
    local on_status off_status

    bash -c "export ALLOY_TRACE=true; exec 9>/dev/null; BASH_XTRACEFD=9; source \"${script}\"; [[ \"\$-\" == *x* ]]; set +x; exec 9>&-"
    on_status=$?
    bash -c "unset ALLOY_TRACE; source \"${script}\"; [[ \"\$-\" != *x* ]]"
    off_status=$?

    assert_equals "0" "${on_status}"
    assert_equals "0" "${off_status}"
}

test_debug_utils_is_safe_to_source_multiple_times() {
    local script="${DEBUG_UTILS_SCRIPT}"
    assert_status_code 0 "bash -c 'source \"${script}\"; source \"${script}\"; log_warn ok >/dev/null'"
}
