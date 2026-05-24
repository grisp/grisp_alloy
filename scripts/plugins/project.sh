#!/usr/bin/env bash
#
# project.sh - Project plugin abstraction and contract (current architecture)
#
# This module is the project-domain abstraction layer on top of
# `scripts/utils/plugin_utils.sh`. Command handlers should consume this module
# instead of iterating plugin functions directly.
#
# Public API provided by this module:
#  1) project_load_plugins SDK_DIR
#     Load plugin files from SDK_DIR/scripts/plugins/project/*.sh.
#
#  2) project_detect_type PROJECT_DIR RESULT_REF
#     Detect project type by calling each `project_<type>_detect`.
#     First detector returning 0 wins and is written into RESULT_REF.
#
#  3) project_build_type TYPE RELEASE_REF PROJECT_DIR PROFILE_SPEC
#     Dispatch build to `project_<type>_build` and return release dir in
#     RELEASE_REF.
#
#  4) project_read_capabilities TYPE ARRAY_NAME
#     Read optional `project_<type>_capabilities` key=value output into
#     ARRAY_NAME with conservative defaults.
#
#  5) project_has_capability TYPE CAPABILITY_NAME
#     Boolean helper returning success only when capability is explicitly true.
#
# Plugin contract for `scripts/plugins/project/<type>.sh`:
#  - Required:
#    * project_<type>_detect PROJECT_DIR
#      Return 0 when PROJECT_DIR matches this type; non-zero otherwise.
#    * project_<type>_build RELEASE_REF PROJECT_DIR PROFILE_SPEC
#      Build project and set RELEASE_REF to absolute release directory path.
#
#  - Optional:
#    * project_<type>_capabilities
#      Print capability key=value lines to stdout.
#
# Current capability keys:
#  - supports_multi_profiles=true|false
#    Default is false when omitted.
#
# Notes:
#  - TYPE values come from plugin filenames (`<type>.sh`), loaded in sorted
#    deterministic order.
#  - Build policy (for example profile validation) is enforced by callers using
#    capabilities after detection.

if [[ "${__ALLOY_PROJECT_PLUGINS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_PROJECT_PLUGINS_SH_LOADED=1

PROJECT_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${PROJECT_PLUGIN_DIR}/../utils/common.sh"
# shellcheck source=scripts/utils/plugin_utils.sh
source "${PROJECT_PLUGIN_DIR}/../utils/plugin_utils.sh"

# project_load_plugins SDK_DIR
# Load project plugins from SDK_DIR/scripts/plugins/project.
# Env/side effects: sources plugin files in deterministic order and fills PLUGIN_TYPES_project.
# Errors: returns 2 for missing arguments, 1 for load failures or empty plugin directories.
project_load_plugins() {
    local sdk_dir="${1:-}"
    [[ -n "${sdk_dir}" ]] || fail "project_load_plugins requires SDK_DIR"

    local plugin_dir="${sdk_dir}/scripts/plugins/project"
    plugin_load project "${plugin_dir}" ||
        fail "Failed to load project plugins from ${plugin_dir}"

    local -n plugin_types_ref="PLUGIN_TYPES_project"
    [[ ${#plugin_types_ref[@]} -gt 0 ]] ||
        fail "No project plugins found in ${plugin_dir}"
}

# project_detect_type PROJECT_DIR RESULT_REF
# Detect the project plugin type for PROJECT_DIR and write it to RESULT_REF.
# Env/side effects: reads PLUGIN_TYPES_project loaded by project_load_plugins.
# Errors: returns 1 when no plugin detects PROJECT_DIR.
project_detect_type() {
    local project_dir="${1:-}"
    local -n result_ref="$2"
    result_ref=""

    local -n plugin_types_ref="PLUGIN_TYPES_project"
    local type_name detect_function
    for type_name in "${plugin_types_ref[@]}"; do
        detect_function="project_${type_name}_detect"
        if ! plugin_has project "${type_name}" detect; then
            log_warn "Skipping project plugin '${type_name}': missing detect action"
            continue
        fi
        if "${detect_function}" "${project_dir}"; then
            result_ref="${type_name}"
            return 0
        fi
    done

    return 1
}

# project_build_type TYPE RELEASE_REF PROJECT_DIR PROFILE_SPEC
# Dispatch project build to the named plugin TYPE.
# Env/side effects: executes plugin build function in current shell.
# Errors: returns 1 if TYPE is missing build action or plugin build fails.
project_build_type() {
    local type_name="${1:-}"
    local -n release_ref="$2"
    local project_dir="${3:-}"
    local profile_spec="${4:-}"

    [[ -n "${type_name}" ]] || fail "project_build_type requires TYPE"
    if ! plugin_has project "${type_name}" build; then
        fail "Selected project plugin '${type_name}' does not implement build"
    fi

    local build_function="project_${type_name}_build"
    "${build_function}" release_ref "${project_dir}" "${profile_spec}"
}

# project_read_capabilities TYPE ARRAY_NAME
# Read project plugin capabilities into ARRAY_NAME; defaults to conservative values when unspecified.
# Env/side effects: writes associative array entries in caller via nameref.
# Errors: returns non-zero only when plugin capability action exists but fails.
project_read_capabilities() {
    local type_name="${1:-}"
    local array_name="${2:-}"
    [[ -n "${type_name}" ]] || fail "project_read_capabilities requires TYPE"
    [[ -n "${array_name}" ]] || fail "project_read_capabilities requires ARRAY_NAME"

    declare -n capabilities_ref="${array_name}"
    capabilities_ref=()
    capabilities_ref["supports_multi_profiles"]="false"

    if plugin_has project "${type_name}" capabilities; then
        plugin_read project "${type_name}" capabilities "${array_name}" ||
            fail "Failed reading capabilities from project plugin '${type_name}'"
        if [[ -z "${capabilities_ref[supports_multi_profiles]:-}" ]]; then
            capabilities_ref["supports_multi_profiles"]="false"
        fi
    fi
}

# project_has_capability TYPE CAPABILITY_NAME
# Return success when project plugin TYPE declares CAPABILITY_NAME=true.
# Env/side effects: reads capabilities through project_read_capabilities.
# Errors: returns 1 when capability is absent/false, or if TYPE/CAPABILITY_NAME are missing.
project_has_capability() {
    local type_name="${1:-}"
    local capability_name="${2:-}"
    [[ -n "${type_name}" ]] || fail "project_has_capability requires TYPE"
    [[ -n "${capability_name}" ]] || fail "project_has_capability requires CAPABILITY_NAME"

    local -A capabilities=()
    project_read_capabilities "${type_name}" capabilities
    [[ "${capabilities[${capability_name}]:-false}" == "true" ]]
}
