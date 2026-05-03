#!/usr/bin/env bash

if [[ -n "${ALLOY_SDK_TOOLS_SH_LOADED:-}" ]]; then
    return 0
fi
ALLOY_SDK_TOOLS_SH_LOADED=1

alloy_sdk_resolve_workspace() {
    if [[ -n "${ALLOY_TARGET_WORKSPACE:-}" ]]; then
        printf '%s\n' "${ALLOY_TARGET_WORKSPACE}"
        return 0
    fi
    if [[ -n "${O:-}" ]]; then
        printf '%s\n' "${O}"
        return 0
    fi
    return 1
}

alloy_sdk_var_suffix() {
    local token="${1:-}"
    token="${token^^}"
    token="${token//[^A-Z0-9]/_}"
    printf '%s\n' "${token}"
}

alloy_sdk_add_output() {
    local output_id="${1:-}"
    local file_path="${2:-}"
    local workspace registry_dir output_file

    [[ -n "${output_id}" ]] || alloy_hook_die "alloy_sdk_add_output requires OUTPUT_ID" || return 2
    [[ -n "${file_path}" ]] || alloy_hook_die "alloy_sdk_add_output requires FILE_PATH" || return 2
    [[ "${file_path}" == /* ]] || alloy_hook_die "alloy_sdk_add_output requires an absolute FILE_PATH: ${file_path}" || return 2
    [[ -e "${file_path}" ]] || alloy_hook_die "alloy_sdk_add_output path does not exist: ${file_path}" || return 2

    workspace="$(alloy_sdk_resolve_workspace)" ||
        alloy_hook_die "alloy_sdk_add_output could not resolve target workspace (ALLOY_TARGET_WORKSPACE or O)" || return 2
    registry_dir="${workspace}/.sdk_outputs"
    output_file="${registry_dir}/${output_id}"

    mkdir -p "${registry_dir}" ||
        alloy_hook_die "alloy_sdk_add_output could not create registry directory: ${registry_dir}" || return 2
    printf '%s\n' "${file_path}" > "${output_file}" ||
        alloy_hook_die "alloy_sdk_add_output could not write registry file: ${output_file}" || return 2
    alloy_hook_debug "Registered sdk output '${output_id}' -> ${file_path}"
}

alloy_sdk_get_output() {
    local aux_id="${1:-}"
    local output_id="${2:-}"
    local aux_suffix output_suffix var_name value

    [[ -n "${aux_id}" ]] || return 2
    [[ -n "${output_id}" ]] || return 2

    aux_suffix="$(alloy_sdk_var_suffix "${aux_id}")"
    output_suffix="$(alloy_sdk_var_suffix "${output_id}")"
    var_name="ALLOY_SDK_OUTPUT_${aux_suffix}_${output_suffix}"
    value="${!var_name:-}"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value}"
        return 0
    fi

    var_name="ALLOY_SDK_OUTPUT_${output_suffix}"
    value="${!var_name:-}"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value}"
        return 0
    fi
    return 1
}

alloy_sdk_has_output() {
    local aux_id="${1:-}"
    local output_id="${2:-}"
    local path
    path="$(alloy_sdk_get_output "${aux_id}" "${output_id}")" || return 1
    [[ -e "${path}" ]]
}
