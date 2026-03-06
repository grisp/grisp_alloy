#!/usr/bin/env bash

if [[ "${__ALLOY_COMMON_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_COMMON_SH_LOADED=1

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
    # shellcheck disable=SC1090
    source "${utility_path}"
}

if ! source_required_utility "scripts/utils/console_utils.sh"; then
    return 2
fi

if ! source_required_utility "scripts/utils/debug_utils.sh"; then
    return 2
fi

fail() {
    die 2 "$*"
}

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

is_non_negative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

export_boolean_env() {
    local name="$1"
    local enabled="$2"
    if [[ "${enabled}" == true ]]; then
        export "${name}=true"
    else
        unset "${name}" || true
    fi
}
