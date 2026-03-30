#!/usr/bin/env bash

if [[ "${__ALLOY_PLUGIN_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_PLUGIN_UTILS_SH_LOADED=1

PLUGIN_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${PLUGIN_UTILS_DIR}/common.sh"

plugin__types_var_name() {
    printf 'PLUGIN_TYPES_%s\n' "$1"
}

plugin__function_name() {
    local category="$1"
    local type_name="$2"
    local action="$3"
    printf '%s_%s_%s\n' "${category}" "${type_name}" "${action}"
}

plugin__require_identity() {
    local field_name="$1"
    local value="$2"
    if [[ -z "${value}" ]]; then
        log_error "${field_name} is required"
        return 2
    fi
}

plugin__read_types_array() {
    local category="$1"
    local array_name
    array_name="$(plugin__types_var_name "${category}")"
    declare -n array_ref="${array_name}"
    printf '%s\n' "${array_ref[@]}"
}

# plugin_load CATEGORY DIR
# Source all `*.sh` plugin files from DIR in deterministic filename order and record loaded type names in `PLUGIN_TYPES_<CATEGORY>`.
# Env/side effects: sources plugin files into the current shell and creates/resets the global `PLUGIN_TYPES_<CATEGORY>` bash array.
# Errors: returns 2 for missing arguments, 1 when DIR is missing/not a directory or a plugin file fails to source, and logs contextual failures.
plugin_load() {
    local category="${1:-}"
    local dir_path="${2:-}"

    plugin__require_identity "CATEGORY" "${category}" || return $?
    plugin__require_identity "DIR" "${dir_path}" || return $?

    if [[ ! -d "${dir_path}" ]]; then
        log_error "Plugin directory not found: ${dir_path}"
        return 1
    fi

    local types_var
    types_var="$(plugin__types_var_name "${category}")"
    declare -g -a "${types_var}=()"
    declare -n types_ref="${types_var}"

    local plugin_file type_name
    shopt -s nullglob
    local -a plugin_files=("${dir_path}"/*.sh)
    shopt -u nullglob

    if [[ ${#plugin_files[@]} -eq 0 ]]; then
        return 0
    fi

    mapfile -t plugin_files < <(printf '%s\n' "${plugin_files[@]}" | LC_ALL=C sort)

    for plugin_file in "${plugin_files[@]}"; do
        # shellcheck disable=SC1090  # plugin path is validated and intentionally sourced from the caller-selected directory
        if ! source "${plugin_file}"; then
            log_error "Failed to load plugin file: ${plugin_file}"
            return 1
        fi
        type_name="$(basename "${plugin_file}" .sh)"
        types_ref+=("${type_name}")
    done
}

# plugin_has CATEGORY TYPE ACTION
# Return success when the plugin function `<CATEGORY>_<TYPE>_<ACTION>` is currently defined in the shell.
# Env/side effects: none.
# Errors: returns 2 for missing arguments, 0 when the function exists, and 1 otherwise.
plugin_has() {
    local category="${1:-}"
    local type_name="${2:-}"
    local action="${3:-}"

    plugin__require_identity "CATEGORY" "${category}" || return $?
    plugin__require_identity "TYPE" "${type_name}" || return $?
    plugin__require_identity "ACTION" "${action}" || return $?

    local function_name
    function_name="$(plugin__function_name "${category}" "${type_name}" "${action}")"
    [[ "$(type -t "${function_name}")" == "function" ]]
}

# plugin_call CATEGORY TYPE ACTION [ARGS...]
# Invoke the plugin function `<CATEGORY>_<TYPE>_<ACTION>` with ARGS and return its exit status.
# Env/side effects: executes the target plugin function in the current shell context; stdout/stderr pass through unchanged.
# Errors: returns 2 for missing arguments, 1 when the plugin function is undefined, otherwise returns the plugin function's exit status and logs failures with category/type/action context.
plugin_call() {
    local category="${1:-}"
    local type_name="${2:-}"
    local action="${3:-}"
    shift 3 || true

    plugin__require_identity "CATEGORY" "${category}" || return $?
    plugin__require_identity "TYPE" "${type_name}" || return $?
    plugin__require_identity "ACTION" "${action}" || return $?

    local function_name
    function_name="$(plugin__function_name "${category}" "${type_name}" "${action}")"
    if ! plugin_has "${category}" "${type_name}" "${action}"; then
        log_error "Plugin ${category}/${type_name} does not implement '${action}'"
        return 1
    fi

    "${function_name}" "$@"
    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        log_error "Plugin ${category}/${type_name} '${action}' failed (exit ${rc})"
    fi
    return ${rc}
}

# plugin_read CATEGORY TYPE ACTION ARRAY_NAME [ARGS...]
# Invoke `<CATEGORY>_<TYPE>_<ACTION>`, require success, and parse `key=value` stdout lines into the associative array named by ARRAY_NAME.
# Env/side effects: replaces the contents of ARRAY_NAME in the caller via nameref assignment; stderr from the plugin passes through unchanged.
# Errors: returns 2 for missing arguments, 1 when the plugin function is undefined, or the plugin exit status when the action fails; logs contextual failures.
plugin_read() {
    local category="${1:-}"
    local type_name="${2:-}"
    local action="${3:-}"
    local array_name="${4:-}"
    shift 4 || true

    plugin__require_identity "CATEGORY" "${category}" || return $?
    plugin__require_identity "TYPE" "${type_name}" || return $?
    plugin__require_identity "ACTION" "${action}" || return $?
    plugin__require_identity "ARRAY_NAME" "${array_name}" || return $?

    local function_name
    function_name="$(plugin__function_name "${category}" "${type_name}" "${action}")"
    if ! plugin_has "${category}" "${type_name}" "${action}"; then
        log_error "Plugin ${category}/${type_name} does not implement '${action}'"
        return 1
    fi

    local output
    output="$("${function_name}" "$@")"
    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        log_error "Plugin ${category}/${type_name} '${action}' failed (exit ${rc})"
        return ${rc}
    fi

    declare -n array_ref="${array_name}"
    array_ref=()

    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" ]] || continue
        [[ "${line}" == *=* ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        array_ref["${key}"]="${value}"
    done <<< "${output}"
}
