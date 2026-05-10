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
__ALLOY_PROGRESS_ACTIVE=0
__ALLOY_PROGRESS_FRAME_INDEX=0
__ALLOY_PROGRESS_LAST_LABEL=""
__ALLOY_PROGRESS_PULSE_PID=""

debug_log_prefix() {
    local prefix="${ALLOY_LOG_PREFIX:-}"
    if [[ -n "${prefix}" ]]; then
        printf '[%s] ' "${prefix}"
    fi
}

debug_prefix_style() {
    local prefix="${ALLOY_LOG_PREFIX:-}"
    if [[ "${prefix}" == alloy:* ]]; then
        printf 'hook_prefix\n'
        return 0
    fi
    printf 'alloy_prefix\n'
}

debug_print_to() {
    local stream="${1:-stdout}"
    shift || true
    case "${stream}" in
        stderr|2) printf '%s\n' "$*" >&2 ;;
        *) printf '%s\n' "$*" ;;
    esac
}

progress_supported() {
    [[ "${TERM:-}" != "dumb" ]] || return 1
    [[ -t 1 ]] || [[ -t 2 ]]
}

progress_clear() {
    if [[ "${__ALLOY_PROGRESS_ACTIVE:-0}" != "1" ]] && [[ -z "${__ALLOY_PROGRESS_PULSE_PID:-}" ]]; then
        return 0
    fi
    printf '\r\033[K' >&2
    __ALLOY_PROGRESS_ACTIVE=0
    __ALLOY_PROGRESS_LAST_LABEL=""
}

progress_tick() {
    local label="${1:-}"
    local -a frames=('|' '/' '-' '\')
    local frame
    local prefix_text prefix_rendered

    progress_supported || return 0
    [[ "${ALLOY_TRACE:-false}" == "false" ]] || return 0
    if [[ "${NO_COLOR:-}" != "" ]]; then
        return 0
    fi

    frame="${frames[__ALLOY_PROGRESS_FRAME_INDEX]}"
    __ALLOY_PROGRESS_FRAME_INDEX=$(((__ALLOY_PROGRESS_FRAME_INDEX + 1) % ${#frames[@]}))

    prefix_text="$(debug_log_prefix)"
    if [[ -n "${prefix_text}" ]]; then
        prefix_rendered="$(console_format_text stdout "$(debug_prefix_style)" "${prefix_text}")"
    else
        prefix_rendered=""
    fi

    printf '\r\033[K%s%s' "${prefix_rendered}" "${frame}" >&2

    __ALLOY_PROGRESS_ACTIVE=1
    __ALLOY_PROGRESS_LAST_LABEL="${label}"
}

progress_pulse_start() {
    local label="${1:-working}"
    progress_supported || return 0
    [[ "${ALLOY_TRACE:-false}" == "false" ]] || return 0
    [[ -z "${NO_COLOR:-}" ]] || return 0
    if [[ -n "${__ALLOY_PROGRESS_PULSE_PID:-}" ]] && kill -0 "${__ALLOY_PROGRESS_PULSE_PID}" 2>/dev/null; then
        return 0
    fi

    (
        while :; do
            progress_tick "${label}"
            sleep 0.2
        done
    ) &
    __ALLOY_PROGRESS_PULSE_PID="$!"
    __ALLOY_PROGRESS_ACTIVE=1
    __ALLOY_PROGRESS_LAST_LABEL="${label}"
}

progress_pulse_stop() {
    local pulse_pid="${__ALLOY_PROGRESS_PULSE_PID:-}"
    if [[ -n "${pulse_pid}" ]] && kill -0 "${pulse_pid}" 2>/dev/null; then
        kill "${pulse_pid}" >/dev/null 2>&1 || true
        wait "${pulse_pid}" >/dev/null 2>&1 || true
    fi
    __ALLOY_PROGRESS_PULSE_PID=""
    progress_clear
}

progress_run() {
    local label="${1:-working}"
    shift || true
    local started_pulse=0
    local interrupted=0
    local status=0
    local old_int_trap old_term_trap

    old_int_trap="$(trap -p INT || true)"
    old_term_trap="$(trap -p TERM || true)"

    trap 'interrupted=1' INT
    trap 'interrupted=1' TERM

    if [[ -z "${__ALLOY_PROGRESS_PULSE_PID:-}" ]] || ! kill -0 "${__ALLOY_PROGRESS_PULSE_PID}" 2>/dev/null; then
        progress_pulse_start "${label}"
        started_pulse=1
    fi

    "$@" || status=$?

    if [[ "${interrupted}" == "1" ]] && [[ "${status}" == "0" ]]; then
        status=130
    fi

    if [[ "${started_pulse}" == "1" ]]; then
        progress_pulse_stop
    fi

    if [[ -n "${old_int_trap}" ]]; then
        eval "${old_int_trap}"
    else
        trap - INT
    fi
    if [[ -n "${old_term_trap}" ]]; then
        eval "${old_term_trap}"
    else
        trap - TERM
    fi

    return "${status}"
}

# log_error MESSAGE...
# Print an error-prefixed message to stderr.
# Env/side effects: writes to stderr; no shell state changes.
# Errors: propagates console_print_to return codes.
log_error() {
    progress_clear
    local raw_prefix prefix level
    raw_prefix="$(debug_log_prefix)"
    prefix="${raw_prefix}"
    if [[ -n "${raw_prefix}" ]]; then
        prefix="$(console_format_text stderr "$(debug_prefix_style)" "${raw_prefix}")"
    fi
    level="$(console_format_text stderr error "ERROR:")"
    debug_print_to stderr "${prefix}${level} $*"
}

# log_warn MESSAGE...
# Print a warning-prefixed message to stderr.
# Env/side effects: writes to stderr; no exports.
# Errors: propagates console_print_to return codes.
log_warn() {
    progress_clear
    local raw_prefix prefix level
    raw_prefix="$(debug_log_prefix)"
    prefix="${raw_prefix}"
    if [[ -n "${raw_prefix}" ]]; then
        prefix="$(console_format_text stderr "$(debug_prefix_style)" "${raw_prefix}")"
    fi
    level="$(console_format_text stderr warn_label "WARN:")"
    debug_print_to stderr "${prefix}${level} $*"
}

# log_info MESSAGE...
# Print an informational message when ALLOY_DEBUG is at least 1.
# Env/side effects: reads ALLOY_DEBUG and may write to stdout; does not mutate the environment.
# Errors: returns 0 when suppressed; otherwise propagates console_print_to return codes.
log_info() {
    if [[ ${ALLOY_DEBUG:-0} -ge 1 ]]; then
        progress_clear
        local raw_prefix prefix
        raw_prefix="$(debug_log_prefix)"
        prefix="${raw_prefix}"
        if [[ -n "${raw_prefix}" ]]; then
            prefix="$(console_format_text stdout "$(debug_prefix_style)" "${raw_prefix}")"
        fi
        local info
        info="$(console_format_text stdout info "INFO:")"
        debug_print_to stdout "${prefix}${info} $*"
    fi
}

# log_debug MESSAGE...
# Print a debug message when ALLOY_DEBUG is at least 2.
# Env/side effects: reads ALLOY_DEBUG and may write to stderr; does not export variables.
# Errors: returns 0 when suppressed; otherwise propagates console_print_to return codes.
log_debug() {
    if [[ ${ALLOY_DEBUG:-0} -ge 2 ]]; then
        progress_clear
        console_print_to stderr debug "$(debug_log_prefix)DEBUG: $*"
    fi
}

# die [EXIT_CODE] MESSAGE...
# Log MESSAGE as an error and terminate the current shell or script with EXIT_CODE (default 1).
# Env/side effects: writes to stderr and exits; callers should only use it in contexts where exiting is intended.
# Errors: this function is terminal and does not return on success.
die() {
    progress_pulse_stop
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
