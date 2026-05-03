#!/usr/bin/env bash

if [[ "${__ALLOY_SDK_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_SDK_UTILS_SH_LOADED=1

SDK_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${SDK_UTILS_DIR}/common.sh"
# shellcheck source=scripts/utils/file_utils.sh
source "${SDK_UTILS_DIR}/file_utils.sh"

ALLOY_SDK_RELOCATION_PLACEHOLDER="${ALLOY_SDK_RELOCATION_PLACEHOLDER:-@@ALLOY_SDK_DIR@@}"

sdk_utils_current_root() {
    local sdk_dir="$1"
    cd "${sdk_dir}" && pwd -P
}

sdk_utils_state_file() {
    printf '%s\n' "${1}/.alloy_sdk_dir"
}

sdk_utils_manifest_file() {
    printf '%s\n' "${1}/.alloy_relocation_manifest"
}

sdk_utils_read_recorded_root() {
    local sdk_dir="$1"
    local state_file
    state_file="$(sdk_utils_state_file "${sdk_dir}")"
    if [[ ! -f "${state_file}" ]]; then
        log_error "SDK relocation state file not found: ${state_file}"
        return 1
    fi

    local recorded_root
    recorded_root="$(head -n 1 "${state_file}")"
    if [[ -z "${recorded_root}" ]]; then
        log_error "SDK relocation state file is empty: ${state_file}"
        return 1
    fi

    printf '%s\n' "${recorded_root}"
}

sdk_utils_escape_sed_pattern() {
    # shellcheck disable=SC2016  # sed regex is intentionally single-quoted so the character class stays literal
    printf '%s' "$1" | sed -e 's/[.[\*^$()+?{|/\\]/\\&/g'
}

sdk_utils_escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

sdk_utils_resolve_manifest_target() {
    local sdk_dir="$1"
    local manifest_entry="$2"
    normalize_path "${sdk_dir}/${manifest_entry}"
}

# check_sdk_relocation SDK_DIR
# Return success when SDK_DIR is already relocated to its current physical path.
# Env/side effects: reads `.alloy_sdk_dir` from SDK_DIR; no writes.
# Errors: returns 2 for missing arguments, 1 for unresolved/invalid relocation state or when relocation is needed.
check_sdk_relocation() {
    local sdk_dir="${1:-}"
    if [[ -z "${sdk_dir}" ]]; then
        log_error "check_sdk_relocation requires SDK_DIR"
        return 2
    fi
    if [[ ! -d "${sdk_dir}" ]]; then
        log_error "SDK directory not found: ${sdk_dir}"
        return 1
    fi

    local current_root recorded_root
    current_root="$(sdk_utils_current_root "${sdk_dir}")" || return 1
    recorded_root="$(sdk_utils_read_recorded_root "${current_root}")" || return 1

    [[ "${recorded_root}" == "${current_root}" ]]
}

# relocate_sdk SDK_DIR
# Replace the recorded SDK root (or relocation placeholder) with the current physical SDK path in manifest-listed files, then update `.alloy_sdk_dir`.
# Env/side effects: rewrites files listed in `.alloy_relocation_manifest` under SDK_DIR and updates `.alloy_sdk_dir`.
# Errors: returns 2 for missing arguments, 1 for invalid SDK relocation metadata, missing listed files, or failed text replacement.
relocate_sdk() {
    local sdk_dir="${1:-}"
    if [[ -z "${sdk_dir}" ]]; then
        log_error "relocate_sdk requires SDK_DIR"
        return 2
    fi
    if [[ ! -d "${sdk_dir}" ]]; then
        log_error "SDK directory not found: ${sdk_dir}"
        return 1
    fi

    local current_root
    current_root="$(sdk_utils_current_root "${sdk_dir}")" || return 1

    local recorded_root
    recorded_root="$(sdk_utils_read_recorded_root "${current_root}")" || return 1
    if [[ "${recorded_root}" == "${current_root}" ]]; then
        return 0
    fi

    local manifest_file
    manifest_file="$(sdk_utils_manifest_file "${current_root}")"
    if [[ ! -f "${manifest_file}" ]]; then
        log_error "SDK relocation manifest not found: ${manifest_file}"
        return 1
    fi

    local escaped_current escaped_placeholder escaped_recorded
    escaped_current="$(sdk_utils_escape_sed_replacement "${current_root}")"
    escaped_placeholder="$(sdk_utils_escape_sed_pattern "${ALLOY_SDK_RELOCATION_PLACEHOLDER}")"
    escaped_recorded="$(sdk_utils_escape_sed_pattern "${recorded_root}")"

    local manifest_entry target_path
    while IFS= read -r manifest_entry || [[ -n "${manifest_entry}" ]]; do
        [[ -n "${manifest_entry}" ]] || continue

        target_path="$(sdk_utils_resolve_manifest_target "${current_root}" "${manifest_entry}")" || return 1
        if [[ "${target_path}" != "${current_root}" ]] && [[ "${target_path}" != "${current_root}/"* ]]; then
            log_error "SDK relocation manifest entry escapes SDK root: ${manifest_entry}"
            return 1
        fi
        if [[ ! -f "${target_path}" ]]; then
            log_error "SDK relocation target listed in manifest is missing: ${target_path}"
            return 1
        fi

        if [[ "${recorded_root}" == "${ALLOY_SDK_RELOCATION_PLACEHOLDER}" ]]; then
            sed -i -e "s|${escaped_placeholder}|${escaped_current}|g" "${target_path}" || return 1
        else
            sed -i \
                -e "s|${escaped_recorded}|${escaped_current}|g" \
                -e "s|${escaped_placeholder}|${escaped_current}|g" \
                "${target_path}" || return 1
        fi
    done < "${manifest_file}"

    printf '%s\n' "${current_root}" > "$(sdk_utils_state_file "${current_root}")"
}

# ensure_sdk_relocated SDK_DIR
# Auto-relocate SDK_DIR on first use when writable, otherwise fail with guidance for `alloy prepare sdk`.
# Env/side effects: may rewrite SDK_DIR files through relocate_sdk and emits user-facing relocation/error messages.
# Errors: returns 2 for missing arguments, 1 for invalid SDK relocation metadata or when relocation is needed but SDK_DIR is not writable.
ensure_sdk_relocated() {
    local sdk_dir="${1:-}"
    if [[ -z "${sdk_dir}" ]]; then
        log_error "ensure_sdk_relocated requires SDK_DIR"
        return 2
    fi

    if check_sdk_relocation "${sdk_dir}"; then
        return 0
    fi

    local current_root
    current_root="$(sdk_utils_current_root "${sdk_dir}")" || return 1
    if [[ ! -w "${current_root}" ]]; then
        log_error "SDK needs relocation but the SDK directory is not writable."
        printf 'Run: alloy prepare sdk\n' >&2
        printf 'Or, if the SDK is installed system-wide: sudo alloy prepare sdk\n' >&2
        return 1
    fi

    print_note "Relocating SDK to ${current_root}..."
    relocate_sdk "${current_root}"
}

# sdk_utils_is_auxiliary_target TARGET_ID
# Return success when TARGET_ID is not the current main target loaded by build-sdk plan metadata.
sdk_utils_is_auxiliary_target() {
    local target_id="$1"
    [[ "${target_id}" != "${ALLOY_PLAN_MAIN_TARGET}" ]]
}

# sdk_utils_var_suffix TOKEN
# Convert TOKEN to an env-var-safe uppercase suffix.
sdk_utils_var_suffix() {
    local token="$1"
    token="${token^^}"
    token="${token//[^A-Z0-9]/_}"
    [[ -n "${token}" ]] || fail "Unable to build variable suffix from empty token"
    printf '%s\n' "${token}"
}

# sdk_utils_stage_auxiliary_output AUX_ID OUTPUT_ID SOURCE_PATH
# Stage one registered auxiliary output into ALLOY_SDK_STAGING_DIR and set BUILD_SDK_STAGED_OUTPUT_PATH.
sdk_utils_stage_auxiliary_output() {
    local aux_id="$1"
    local output_id="$2"
    local source_path="$3"
    local output_stage_dir="${ALLOY_SDK_STAGING_DIR}/auxiliary/${aux_id}/outputs/${output_id}"

    rm -rf "${output_stage_dir}"
    mkdir -p "${output_stage_dir}"

    if [[ -d "${source_path}" ]]; then
        cp -a "${source_path%/}/." "${output_stage_dir}/"
        BUILD_SDK_STAGED_OUTPUT_PATH="${output_stage_dir}"
        return 0
    fi

    cp -a "${source_path}" "${output_stage_dir}/"
    BUILD_SDK_STAGED_OUTPUT_PATH="${output_stage_dir}/$(basename "${source_path}")"
}

sdk_utils_array_contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

# sdk_utils_collect_auxiliary_sdk_outputs
# Orchestrator-side collection/validation/staging of auxiliary .sdk_outputs and ALLOY_SDK_OUTPUT_* mapping export.
sdk_utils_collect_auxiliary_sdk_outputs() {
    BUILD_SDK_AUX_OUTPUT_KEYS=()
    declare -gA BUILD_SDK_AUX_OUTPUT_STAGED_PATHS=()
    declare -gA BUILD_SDK_OUTPUT_ALIAS_COUNTS=()
    declare -gA BUILD_SDK_OUTPUT_ALIAS_PATHS=()
    declare -gA BUILD_SDK_OUTPUT_ALIAS_UNIQUE_AUX=()
    BUILD_SDK_STAGED_AUX_OUTPUT_COUNT=0

    local target_id
    for target_id in "${ALLOY_PLAN_TARGET_IDS[@]}"; do
        sdk_utils_is_auxiliary_target "${target_id}" || continue

        local context_file="${ALLOY_SDK_TARGETS_DIR}/${target_id}/alloy_context.sh"
        local workspace_dir="${ALLOY_SDK_TARGETS_DIR}/${target_id}/workspace"
        local sdk_outputs_dir="${workspace_dir}/.sdk_outputs"
        local output_id output_reg_file source_path key aux_var_suffix output_var_suffix staged_path
        local -a declared_outputs=()

        [[ -f "${context_file}" ]] ||
            fail "Auxiliary context is missing for sdk output collection: ${context_file}"
        # shellcheck disable=SC1090 # target context is generated by smelterl for this SDK build.
        source "${context_file}"

        if ! declare -p ALLOY_SDK_OUTPUTS >/dev/null 2>&1; then
            log_debug "Auxiliary target '${target_id}' has no ALLOY_SDK_OUTPUTS declaration."
            continue
        fi
        declared_outputs=("${ALLOY_SDK_OUTPUTS[@]}")
        [[ ${#declared_outputs[@]} -gt 0 ]] || continue

        [[ -d "${sdk_outputs_dir}" ]] ||
            fail "Missing sdk output registry for auxiliary target '${target_id}': ${sdk_outputs_dir}"

        for output_id in "${declared_outputs[@]}"; do
            [[ -n "${output_id}" ]] ||
                fail "Auxiliary target '${target_id}' declares an empty sdk output id"

            output_reg_file="${sdk_outputs_dir}/${output_id}"
            [[ -f "${output_reg_file}" ]] ||
                fail "Missing registered sdk output '${output_id}' for auxiliary target '${target_id}': ${output_reg_file}"

            source_path="$(<"${output_reg_file}")"
            [[ -n "${source_path}" ]] ||
                fail "Registered sdk output '${output_id}' for auxiliary target '${target_id}' is empty"
            [[ "${source_path}" == /* ]] ||
                fail "Registered sdk output '${output_id}' for auxiliary target '${target_id}' must be an absolute path: ${source_path}"
            [[ -e "${source_path}" ]] ||
                fail "Registered sdk output '${output_id}' for auxiliary target '${target_id}' does not exist: ${source_path}"

            sdk_utils_stage_auxiliary_output "${target_id}" "${output_id}" "${source_path}"
            staged_path="${BUILD_SDK_STAGED_OUTPUT_PATH}"

            key="${target_id}|${output_id}"
            BUILD_SDK_AUX_OUTPUT_KEYS+=("${key}")
            BUILD_SDK_AUX_OUTPUT_STAGED_PATHS["${key}"]="${staged_path}"
            BUILD_SDK_STAGED_AUX_OUTPUT_COUNT=$((BUILD_SDK_STAGED_AUX_OUTPUT_COUNT + 1))

            BUILD_SDK_OUTPUT_ALIAS_COUNTS["${output_id}"]=$(( ${BUILD_SDK_OUTPUT_ALIAS_COUNTS["${output_id}"]:-0} + 1 ))
            BUILD_SDK_OUTPUT_ALIAS_PATHS["${output_id}"]="${staged_path}"
            BUILD_SDK_OUTPUT_ALIAS_UNIQUE_AUX["${output_id}"]="${target_id}"
        done

        local registered_output_file registered_output_id
        shopt -s nullglob
        for registered_output_file in "${sdk_outputs_dir}"/*; do
            registered_output_id="$(basename "${registered_output_file}")"
            if ! sdk_utils_array_contains "${registered_output_id}" "${declared_outputs[@]}"; then
                fail "Auxiliary target '${target_id}' registered undeclared sdk output '${registered_output_id}'"
            fi
        done
        shopt -u nullglob
    done

    for key in "${BUILD_SDK_AUX_OUTPUT_KEYS[@]}"; do
        local aux_id="${key%%|*}"
        local output_id_key="${key#*|}"
        aux_var_suffix="$(sdk_utils_var_suffix "${aux_id}")"
        output_var_suffix="$(sdk_utils_var_suffix "${output_id_key}")"
        export "ALLOY_SDK_OUTPUT_${aux_var_suffix}_${output_var_suffix}=${BUILD_SDK_AUX_OUTPUT_STAGED_PATHS[${key}]}"
    done

    local alias_output_id alias_count alias_suffix
    for alias_output_id in "${!BUILD_SDK_OUTPUT_ALIAS_COUNTS[@]}"; do
        alias_count="${BUILD_SDK_OUTPUT_ALIAS_COUNTS[${alias_output_id}]}"
        if [[ "${alias_count}" -eq 1 ]]; then
            alias_suffix="$(sdk_utils_var_suffix "${alias_output_id}")"
            export "ALLOY_SDK_OUTPUT_${alias_suffix}=${BUILD_SDK_OUTPUT_ALIAS_PATHS[${alias_output_id}]}"
        fi
    done
}

# sdk_utils_inject_main_context_sdk_outputs
# Append orchestrator-resolved ALLOY_SDK_OUTPUT_* exports to main target alloy_context.sh.
sdk_utils_inject_main_context_sdk_outputs() {
    local main_context_file="${ALLOY_SDK_TARGETS_DIR}/${ALLOY_PLAN_MAIN_TARGET}/alloy_context.sh"
    [[ -f "${main_context_file}" ]] ||
        fail "Main target context is missing for sdk output injection: ${main_context_file}"

    {
        printf '\n'
        printf '## Auxiliary SDK Outputs (orchestrator injected) ##\n'
        local key aux_id output_id aux_suffix output_suffix staged_path
        for key in "${BUILD_SDK_AUX_OUTPUT_KEYS[@]}"; do
            aux_id="${key%%|*}"
            output_id="${key#*|}"
            aux_suffix="$(sdk_utils_var_suffix "${aux_id}")"
            output_suffix="$(sdk_utils_var_suffix "${output_id}")"
            staged_path="${BUILD_SDK_AUX_OUTPUT_STAGED_PATHS[${key}]}"
            printf 'export ALLOY_SDK_OUTPUT_%s_%s=%q\n' "${aux_suffix}" "${output_suffix}" "${staged_path}"
        done

        local alias_output_id alias_count alias_suffix
        for alias_output_id in "${!BUILD_SDK_OUTPUT_ALIAS_COUNTS[@]}"; do
            alias_count="${BUILD_SDK_OUTPUT_ALIAS_COUNTS[${alias_output_id}]}"
            if [[ "${alias_count}" -eq 1 ]]; then
                alias_suffix="$(sdk_utils_var_suffix "${alias_output_id}")"
                printf 'export ALLOY_SDK_OUTPUT_%s=%q\n' "${alias_suffix}" "${BUILD_SDK_OUTPUT_ALIAS_PATHS[${alias_output_id}]}"
            fi
        done
    } >> "${main_context_file}"
}
