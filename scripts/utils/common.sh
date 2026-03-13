#!/usr/bin/env bash

if [[ "${__ALLOY_COMMON_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_COMMON_SH_LOADED=1

# resolve_script_dir SOURCE_PATH
# Resolve SOURCE_PATH through symlinks and print the physical parent directory on stdout.
# Env/side effects: changes directory during execution, so callers should normally use command substitution.
# Errors: relies on underlying cd/readlink/pwd behavior; invalid paths surface as command failures.
resolve_script_dir() {
    local source_path="$1"
    while [[ -L "${source_path}" ]]; do
        local source_dir
        source_dir="$(cd "$(dirname "${source_path}")" && pwd -P)"
        source_path="$(readlink "${source_path}")"
        if [[ "${source_path}" != /* ]]; then
            source_path="${source_dir}/${source_path}"
        fi
    done
    cd "$(dirname "${source_path}")" && pwd -P
}

if [[ -z "${ALLOY_ROOT:-}" ]]; then
    ALLOY_ROOT="$(resolve_script_dir "${BASH_SOURCE[0]}")/../.."
    ALLOY_ROOT="$(cd "${ALLOY_ROOT}" && pwd -P)"
fi
ALLOY_ROOT_DIR="${ALLOY_ROOT_DIR:-${ALLOY_ROOT}}"
export ALLOY_ROOT ALLOY_ROOT_DIR

# source_required_utility RELPATH
# Source a utility file located under ALLOY_ROOT using a repo-relative path.
# Env/side effects: reads ALLOY_ROOT and loads functions/variables from the target file into the current shell.
# Errors: prints a direct error to stderr and returns 2 when RELPATH is missing or the file does not exist.
source_required_utility() {
    local utility_relpath="${1:-}"
    if [[ -z "${utility_relpath}" ]]; then
        echo "ERROR: source_required_utility requires a utility path" >&2
        return 2
    fi

    local utility_path="${ALLOY_ROOT}/${utility_relpath}"
    if [[ ! -f "${utility_path}" ]]; then
        echo "ERROR: Missing required utility: ${utility_path}" >&2
        return 2
    fi
    # shellcheck disable=SC1090  # dynamic path under ALLOY_ROOT is intentional for utility loading
    source "${utility_path}"
}

if ! source_required_utility "scripts/utils/console_utils.sh"; then
    return 2
fi

if ! source_required_utility "scripts/utils/debug_utils.sh"; then
    return 2
fi

# fail MESSAGE...
# Abort the current command path with exit code 2 through debug_utils.sh::die.
# Env/side effects: writes an error message and exits the current shell context.
# Errors: terminal helper; does not return on success.
fail() {
    die 2 "$*"
}

# require_var VAR_NAME [MESSAGE]
# Ensure the named shell variable is set and non-empty.
# Env/side effects: reads the caller's variable namespace; no exports on success.
# Errors: exits with code 2 via die when VAR_NAME is missing/empty or when VAR_NAME itself is omitted.
require_var() {
    local var_name="${1:-}"
    if [[ -z "${var_name}" ]]; then
        die 2 "require_var requires a variable name"
    fi

    if [[ -z "${!var_name:-}" ]]; then
        local message="${2:-Required variable is not set: ${var_name}}"
        die 2 "${message}"
    fi
}

# is_non_negative_integer VALUE
# Test whether VALUE is a base-10 non-negative integer.
# Env/side effects: none.
# Errors: returns 0 on match, 1 on mismatch.
is_non_negative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# export_boolean_env NAME ENABLED
# Export NAME=true when ENABLED is `true`, otherwise remove NAME from the environment.
# Env/side effects: mutates the exported environment for NAME.
# Errors: returns 0; treats any non-`true` value as false/off.
export_boolean_env() {
    local name="$1"
    local enabled="$2"
    if [[ "${enabled}" == true ]]; then
        export "${name}=true"
    else
        unset "${name}" || true
    fi
}

# require_command COMMAND
# Ensure COMMAND is available on PATH.
# Env/side effects: reads PATH; no exports.
# Errors: returns 2 for missing arguments, 127 for unavailable commands, and logs failures to stderr.
require_command() {
    local command_name="${1:-}"
    if [[ -z "${command_name}" ]]; then
        log_error "require_command requires a command name"
        return 2
    fi

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        log_error "Required command not found: ${command_name}"
        return 127
    fi
}

# require_commands COMMAND...
# Ensure every listed command is available on PATH.
# Env/side effects: reads PATH; no exports.
# Errors: returns 2 when called without arguments, otherwise propagates the first require_command failure.
require_commands() {
    if [[ $# -eq 0 ]]; then
        log_error "require_commands requires at least one command name"
        return 2
    fi

    local command_name
    for command_name in "$@"; do
        require_command "${command_name}" || return $?
    done
}
