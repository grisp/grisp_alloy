#!/usr/bin/env bash

if [[ -n "${ALLOY_DEBUG_TOOLS_SH_LOADED:-}" ]]; then
    return 0
fi
ALLOY_DEBUG_TOOLS_SH_LOADED=1

alloy_debug_level() {
    local debug_level="${ALLOY_DEBUG:-0}"
    if [[ "${debug_level}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "${debug_level}"
        return 0
    fi
    printf '0\n'
}

alloy_log_prefix() {
    if [[ -n "${ALLOY_LOG_PREFIX:-}" ]]; then
        printf '[%s]' "${ALLOY_LOG_PREFIX}"
        return 0
    fi
    local hook_type="${ALLOY_HOOK_TYPE:-hook}"
    local nugget_id="${ALLOY_NUGGET:-global}"
    printf '[%s:%s]' "${hook_type}" "${nugget_id}"
}

alloy_log_stderr() {
    local level="$1"
    shift
    printf '%s %s: %s\n' "$(alloy_log_prefix)" "${level}" "$*" >&2
}

alloy_log_stdout() {
    local level="$1"
    shift
    printf '%s %s: %s\n' "$(alloy_log_prefix)" "${level}" "$*"
}

# alloy_log_format_path PATH
# Print PATH as root-relative when possible, otherwise as an absolute path.
# Env/side effects: reads ALLOY_ROOT_DIR and current working directory.
# Errors: returns 2 when PATH is empty.
alloy_log_format_path() {
    local path_value="${1:-}"
    local root_path cwd
    if [[ -z "${path_value}" ]]; then
        return 2
    fi
    if [[ "${path_value}" != /* ]]; then
        printf '%s\n' "${path_value}"
        return 0
    fi

    root_path=""
    if [[ -n "${ALLOY_ROOT_DIR:-}" ]] && [[ -d "${ALLOY_ROOT_DIR}" ]]; then
        root_path="$(cd "${ALLOY_ROOT_DIR}" && pwd -P)"
    fi
    if [[ -n "${root_path}" ]]; then
        if [[ "${path_value}" == "${root_path}" ]]; then
            printf '.\n'
            return 0
        fi
        if [[ "${root_path}" != "/" ]] && [[ "${path_value}" == "${root_path}/"* ]]; then
            printf '%s\n' "${path_value#${root_path}/}"
            return 0
        fi
    fi

    cwd="$(pwd -P)"
    if [[ "${path_value}" == "${cwd}" ]]; then
        printf '.\n'
        return 0
    fi
    if [[ "${cwd}" == "/" ]]; then
        printf '%s\n' "${path_value#/}"
        return 0
    fi
    if [[ "${path_value}" == "${cwd}/"* ]]; then
        printf '%s\n' "${path_value#${cwd}/}"
        return 0
    fi
    printf '%s\n' "${path_value}"
}

alloy_log_error() {
    alloy_log_stderr "ERROR" "$*"
}

alloy_log_warn() {
    alloy_log_stderr "WARN" "$*"
}

alloy_log_info() {
    if [[ "$(alloy_debug_level)" -ge 1 ]]; then
        alloy_log_stdout "INFO" "$*"
    fi
}

alloy_log_debug() {
    if [[ "$(alloy_debug_level)" -ge 2 ]]; then
        alloy_log_stderr "DEBUG" "$*"
    fi
}

alloy_enter_hidden() {
    if [[ "${-}" == *x* ]]; then
        ALLOY_HIDDEN_XTRACE_RESTORE=1
        set +x
    else
        ALLOY_HIDDEN_XTRACE_RESTORE=0
    fi
}

alloy_leave_hidden() {
    if [[ "${ALLOY_HIDDEN_XTRACE_RESTORE:-0}" == "1" ]]; then
        set -x
    fi
}

alloy_die() {
    local exit_code=1
    if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
        exit_code="$1"
        shift
    fi
    alloy_log_error "$*"
    exit "${exit_code}"
}
