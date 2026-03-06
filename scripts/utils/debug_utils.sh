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

log_error() {
    console_print_to stderr error "ERROR: $*"
}

log_warn() {
    console_print_to stderr warn "WARN: $*"
}

log_info() {
    if [[ ${ALLOY_DEBUG:-0} -ge 1 ]]; then
        console_print_to stdout info "INFO: $*"
    fi
}

log_debug() {
    if [[ ${ALLOY_DEBUG:-0} -ge 2 ]]; then
        console_print_to stderr debug "DEBUG: $*"
    fi
}

die() {
    local code=1
    if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        code="$1"
        shift
    fi
    log_error "$*"
    exit "${code}"
}

set_debug_level() {
    local level="${1:-0}"
    if ! [[ "${level}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid debug level: ${level}"
        return 2
    fi
    ALLOY_DEBUG="${level}"
    export ALLOY_DEBUG
}

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

enter_hidden() {
    if [[ "$-" == *x* ]]; then
        __ALLOY_HIDDEN_TRACE_STACK+=(1)
        set +x
    else
        __ALLOY_HIDDEN_TRACE_STACK+=(0)
    fi
}

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
