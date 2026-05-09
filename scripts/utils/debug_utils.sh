#!/usr/bin/env bash

if [[ "${__ALLOY_DEBUG_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_DEBUG_UTILS_SH_LOADED=1

DEBUG_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/console_utils.sh
source "${DEBUG_UTILS_DIR}/console_utils.sh"

# shellcheck disable=SC2034  # global stack state used by enter_hidden/leave_hidden
__ALLOY_HIDDEN_TRACE_STACK=()

debug_log_prefix() {
    local prefix="${ALLOY_LOG_PREFIX:-}"
    if [[ -n "${prefix}" ]]; then
        printf '[%s] ' "${prefix}"
    fi
}

# log_error MESSAGE...
# Print an error-prefixed message to stderr.
# Env/side effects: writes to stderr; no shell state changes.
# Errors: propagates console_print_to return codes.
log_error() {
    console_print_to stderr error "$(debug_log_prefix)ERROR: $*"
}

# log_warn MESSAGE...
# Print a warning-prefixed message to stderr.
# Env/side effects: writes to stderr; no exports.
# Errors: propagates console_print_to return codes.
log_warn() {
    console_print_to stderr warn "$(debug_log_prefix)WARN: $*"
}

# log_info MESSAGE...
# Print an informational message when ALLOY_DEBUG is at least 1.
# Env/side effects: reads ALLOY_DEBUG and may write to stdout; does not mutate the environment.
# Errors: returns 0 when suppressed; otherwise propagates console_print_to return codes.
log_info() {
    if [[ ${ALLOY_DEBUG:-0} -ge 1 ]]; then
        console_print_to stdout info "$(debug_log_prefix)INFO: $*"
    fi
}

# log_debug MESSAGE...
# Print a debug message when ALLOY_DEBUG is at least 2.
# Env/side effects: reads ALLOY_DEBUG and may write to stderr; does not export variables.
# Errors: returns 0 when suppressed; otherwise propagates console_print_to return codes.
log_debug() {
    if [[ ${ALLOY_DEBUG:-0} -ge 2 ]]; then
        console_print_to stderr debug "$(debug_log_prefix)DEBUG: $*"
    fi
}

# die [EXIT_CODE] MESSAGE...
# Log MESSAGE as an error and terminate the current shell or script with EXIT_CODE (default 1).
# Env/side effects: writes to stderr and exits; callers should only use it in contexts where exiting is intended.
# Errors: this function is terminal and does not return on success.
die() {
    local code=1
    if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        code="$1"
        shift
    fi
    log_error "$*"
    exit "${code}"
}

# set_debug_level LEVEL
# Validate LEVEL as a non-negative integer and export it as ALLOY_DEBUG.
# Env/side effects: updates exported ALLOY_DEBUG; does not toggle xtrace.
# Errors: returns 2 and logs on invalid LEVEL input.
set_debug_level() {
    local level="${1:-0}"
    if ! [[ "${level}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid debug level: ${level}"
        return 2
    fi
    ALLOY_DEBUG="${level}"
    export ALLOY_DEBUG
}

# set_trace ENABLED
# Enable or disable bash xtrace and synchronize the exported ALLOY_TRACE flag.
# Env/side effects: mutates shell tracing state (`set -x` / `set +x`) and ALLOY_TRACE.
# Errors: returns 2 and logs when ENABLED is not a recognized boolean-like token.
set_trace() {
    local enabled="${1:-false}"
    case "${enabled}" in
        true|1|yes|on)
            export ALLOY_TRACE=true
            set -x
            ;;
        false|0|no|off)
            unset ALLOY_TRACE || true
            set +x
            ;;
        *)
            log_error "Invalid trace value: ${enabled}"
            return 2
            ;;
    esac
}

# enter_hidden
# Temporarily disable xtrace while remembering whether it was active.
# Env/side effects: appends state to __ALLOY_HIDDEN_TRACE_STACK and may disable xtrace.
# Errors: returns 0; intended to pair with leave_hidden even around early returns.
enter_hidden() {
    if [[ "$-" == *x* ]]; then
        __ALLOY_HIDDEN_TRACE_STACK+=(1)
        set +x
    else
        __ALLOY_HIDDEN_TRACE_STACK+=(0)
    fi
}

# leave_hidden
# Restore the xtrace state captured by the most recent enter_hidden call.
# Env/side effects: pops __ALLOY_HIDDEN_TRACE_STACK and may re-enable xtrace.
# Errors: returns 0 when the stack is empty; otherwise restores the recorded trace state.
leave_hidden() {
    local stack_size="${#__ALLOY_HIDDEN_TRACE_STACK[@]}"
    if [[ "${stack_size}" -eq 0 ]]; then
        return 0
    fi

    local last_index=$((stack_size - 1))
    local should_restore="${__ALLOY_HIDDEN_TRACE_STACK[$last_index]}"
    unset '__ALLOY_HIDDEN_TRACE_STACK[$last_index]'

    if [[ "${should_restore}" == "1" ]]; then
        set -x
    fi
}

if ! set_debug_level "${ALLOY_DEBUG:-0}"; then
    set_debug_level 0
fi
if [[ "${ALLOY_TRACE:-}" == "true" ]]; then
    set_trace true
else
    set_trace false
fi
