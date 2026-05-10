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

sdk_utils_display_path() {
    local path_value="${1:-}"
    local cwd
    cwd="$(pwd -P)"
    display_path_for_root "${cwd}" "${path_value}"
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

    print_note "Relocating SDK to $(sdk_utils_display_path "${current_root}")..."
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

sdk_utils_manifest_product_version() {
    local manifest_file="$1"
    local version
    version="$(sed -n 's/.*{product_version,[[:space:]]*<<"\([^"]\+\)">>.*/\1/p' "${manifest_file}" | head -n 1)"
    if [[ -z "${version}" ]]; then
        version="0.0.0"
    fi
    printf '%s\n' "${version}"
}

sdk_utils_is_elf_file() {
    local file_path="$1"
    local magic_hex
    magic_hex="$(dd if="${file_path}" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')" || return 1
    [[ "${magic_hex}" == "7f454c46" ]]
}

sdk_utils_split_rpath_entries() {
    local rpath_value="$1"
    local -n output_ref="$2"
    output_ref=()
    [[ -n "${rpath_value}" ]] || return 0

    local entry
    IFS=':' read -r -a output_ref <<< "${rpath_value}"
    for entry in "${output_ref[@]}"; do
        [[ -n "${entry}" ]] || return 1
    done
}

sdk_utils_is_origin_relative_rpath_entry() {
    local entry="$1"
    [[ "${entry}" == '$ORIGIN' ]] ||
        [[ "${entry}" == '$ORIGIN/'* ]] ||
        [[ "${entry}" == '${ORIGIN}' ]] ||
        [[ "${entry}" == '${ORIGIN}/'* ]]
}

sdk_utils_is_non_dynamic_rpath_probe_error() {
    local patchelf_error_output="$1"
    [[ "${patchelf_error_output}" == *".dynamic"* ]] ||
        [[ "${patchelf_error_output}" == *"wrong ELF type"* ]] ||
        [[ "${patchelf_error_output}" == *"not an ELF executable"* ]] ||
        [[ "${patchelf_error_output}" == *"not a dynamic executable"* ]]
}

sdk_utils_make_origin_relative_rpath_entry() {
    local sdk_dir="$1"
    local elf_path="$2"
    local entry="$3"
    local target_dir relative_dir

    if [[ "${entry}" != /* ]]; then
        return 1
    fi
    target_dir="$(normalize_path "${entry}")" || return 1
    if [[ "${target_dir}" != "${sdk_dir}" ]] && [[ "${target_dir}" != "${sdk_dir}/"* ]]; then
        return 1
    fi

    relative_dir="$(relative_path "$(dirname "${elf_path}")" "${target_dir}")" || return 1
    if [[ "${relative_dir}" == "." ]]; then
        printf '$ORIGIN\n'
    else
        printf '$ORIGIN/%s\n' "${relative_dir}"
    fi
}

sdk_utils_is_target_sysroot_elf_path() {
    local sdk_dir="$1"
    local elf_path="$2"
    [[ "${elf_path}" == "${sdk_dir}/host/"*"/sysroot/"* ]] ||
        [[ "${elf_path}" == "${sdk_dir}/staging/"*"/sysroot/"* ]] ||
        [[ "${elf_path}" == "${sdk_dir}/staging/usr/"* ]] ||
        [[ "${elf_path}" == "${sdk_dir}/staging/lib/"* ]]
}

# verify_elf_rpaths SDK_DIR
# Scan embedded SDK trees for ELF files, enforce $ORIGIN-relative RPATHs, and rewrite fixable absolute RPATH entries with patchelf.
# Env/side effects: requires `patchelf` on PATH; updates ELF RPATH entries in place when absolute paths can be converted to SDK-internal $ORIGIN-relative paths.
# Errors: returns 2 for missing arguments, 1 for missing SDK trees, malformed/unfixable RPATH entries, or patchelf failures.
verify_elf_rpaths() {
    local sdk_dir="${1:-}"
    if [[ -z "${sdk_dir}" ]]; then
        log_error "verify_elf_rpaths requires SDK_DIR"
        return 2
    fi
    [[ -d "${sdk_dir}/host" ]] || fail "Missing SDK host tree for ELF RPATH verification: ${sdk_dir}/host"
    [[ -d "${sdk_dir}/images" ]] || fail "Missing SDK images tree for ELF RPATH verification: ${sdk_dir}/images"
    [[ -d "${sdk_dir}/motherlode" ]] || fail "Missing SDK motherlode tree for ELF RPATH verification: ${sdk_dir}/motherlode"
    require_command patchelf || return $?

    local elf_path rpath_value updated_rpath entry patched patchelf_error
    local -a rpath_entries=() rewritten_entries=() scan_dirs=(
        "${sdk_dir}/host"
        "${sdk_dir}/images"
        "${sdk_dir}/motherlode"
    )
    if [[ -e "${sdk_dir}/staging" ]]; then
        scan_dirs+=("${sdk_dir}/staging")
    fi

    while IFS= read -r elf_path; do
        sdk_utils_is_elf_file "${elf_path}" || continue
        if sdk_utils_is_target_sysroot_elf_path "${sdk_dir}" "${elf_path}"; then
            log_debug "Skipping target-sysroot ELF for RPATH verification: $(sdk_utils_display_path "${elf_path}")"
            continue
        fi
        if ! rpath_value="$(patchelf --print-rpath "${elf_path}" 2>&1)"; then
            patchelf_error="${rpath_value}"
            if sdk_utils_is_non_dynamic_rpath_probe_error "${patchelf_error}"; then
                log_debug "Skipping non-dynamic ELF for RPATH verification: $(sdk_utils_display_path "${elf_path}")"
                continue
            fi
            fail "Unable to read ELF RPATH: ${elf_path}"
        fi
        [[ -n "${rpath_value}" ]] || continue

        sdk_utils_split_rpath_entries "${rpath_value}" rpath_entries ||
            fail "Malformed ELF RPATH entry list for ${elf_path}: ${rpath_value}"

        rewritten_entries=()
        patched=false
        for entry in "${rpath_entries[@]}"; do
            if sdk_utils_is_origin_relative_rpath_entry "${entry}"; then
                rewritten_entries+=("${entry}")
                continue
            fi
            updated_rpath="$(sdk_utils_make_origin_relative_rpath_entry "${sdk_dir}" "${elf_path}" "${entry}")" ||
                fail "Unfixable ELF RPATH entry for ${elf_path}: ${entry}"
            rewritten_entries+=("${updated_rpath}")
            patched=true
        done

        if [[ "${patched}" == "true" ]]; then
            updated_rpath="$(IFS=:; printf '%s' "${rewritten_entries[*]}")"
            log_info "Rewriting ELF RPATH: $(sdk_utils_display_path "${elf_path}")"
            log_debug "ELF RPATH old=${rpath_value}"
            log_debug "ELF RPATH new=${updated_rpath}"
            patchelf --set-rpath "${updated_rpath}" "${elf_path}" ||
                fail "Failed to rewrite ELF RPATH for ${elf_path}"
            rpath_value="$(patchelf --print-rpath "${elf_path}" 2>/dev/null)" ||
                fail "Unable to re-read ELF RPATH after rewrite: ${elf_path}"
            sdk_utils_split_rpath_entries "${rpath_value}" rpath_entries ||
                fail "Malformed ELF RPATH after rewrite for ${elf_path}: ${rpath_value}"
        fi

        for entry in "${rpath_entries[@]}"; do
            sdk_utils_is_origin_relative_rpath_entry "${entry}" ||
                fail "ELF RPATH remains non-relocatable for ${elf_path}: ${entry}"
        done
    done < <(find "${scan_dirs[@]}" -type f | sort)
}

sdk_utils_sanitize_text_paths() {
    local sdk_dir="$1"
    local source_host_root="$2"
    local source_images_root="$3"
    local source_motherlode_root="$4"
    local manifest_file
    manifest_file="$(sdk_utils_manifest_file "${sdk_dir}")"
    : > "${manifest_file}"

    local file rel_path updated
    while IFS= read -r file; do
        if ! grep -Iq . "${file}" 2>/dev/null; then
            continue
        fi

        updated=false
        if grep -Fq "${source_host_root}" "${file}" 2>/dev/null; then
            sed -i -e "s|${source_host_root}|${ALLOY_SDK_RELOCATION_PLACEHOLDER}/host|g" "${file}"
            updated=true
        fi
        if grep -Fq "${source_images_root}" "${file}" 2>/dev/null; then
            sed -i -e "s|${source_images_root}|${ALLOY_SDK_RELOCATION_PLACEHOLDER}/images|g" "${file}"
            updated=true
        fi
        if grep -Fq "${source_motherlode_root}" "${file}" 2>/dev/null; then
            sed -i -e "s|${source_motherlode_root}|${ALLOY_SDK_RELOCATION_PLACEHOLDER}/motherlode|g" "${file}"
            updated=true
        fi

        if [[ "${updated}" == "true" ]] && grep -Fq "${ALLOY_SDK_RELOCATION_PLACEHOLDER}" "${file}" 2>/dev/null; then
            rel_path="$(relative_path "${sdk_dir}" "${file}")"
            printf '%s\n' "${rel_path}" >> "${manifest_file}"
        fi
    done < <(find "${sdk_dir}" -type f | sort)

    if [[ -s "${manifest_file}" ]]; then
        sort -u -o "${manifest_file}" "${manifest_file}"
    fi

    printf '%s\n' "${ALLOY_SDK_RELOCATION_PLACEHOLDER}" > "$(sdk_utils_state_file "${sdk_dir}")"
}

# pack_sdk BUILD_ROOT PRODUCT_ID
# Assemble a packed SDK directory and tarball from the completed build-sdk workspace and return tarball path on stdout.
# Env/side effects: reads ALLOY_SDK_* workspace vars, writes packed SDK tree under ALLOY_SDK_STAGING_DIR, emits tarball under ALLOY_ARTEFACT_DIR/sdk.
# Errors: returns 2 for missing arguments, 1 for missing required build artefacts or failed copy/archive operations.
pack_sdk() {
    local build_root="${1:-}"
    local product_id="${2:-}"
    if [[ -z "${build_root}" ]] || [[ -z "${product_id}" ]]; then
        log_error "pack_sdk requires BUILD_ROOT and PRODUCT_ID"
        return 2
    fi

    local main_target="${ALLOY_PLAN_MAIN_TARGET:-main}"
    local main_workspace="${ALLOY_SDK_TARGETS_DIR}/${main_target}/workspace"
    local main_context="${ALLOY_SDK_TARGETS_DIR}/${main_target}/alloy_context.sh"
    local manifest_path="${ALLOY_SDK_STAGING_DIR}/ALLOY_SDK_MANIFEST"
    local legal_info_dir="${ALLOY_SDK_STAGING_DIR}/legal-info"
    local sdk_dir="${ALLOY_SDK_STAGING_DIR}"
    local source_host="${main_workspace}/host"
    local source_images="${main_workspace}/images"
    local source_staging="${main_workspace}/staging"
    local source_motherlode="${ALLOY_MOTHERLODE}"

    local alloy_root="${ALLOY_ROOT_DIR:-${ALLOY_ROOT:-}}"
    [[ -n "${alloy_root}" ]] || fail "ALLOY_ROOT_DIR must be set for SDK packing"
    [[ -f "${alloy_root}/alloy" ]] || fail "Missing alloy entrypoint for SDK packing: ${alloy_root}/alloy"
    [[ -d "${alloy_root}/scripts" ]] || fail "Missing scripts directory for SDK packing: ${alloy_root}/scripts"
    [[ -f "${main_context}" ]] || fail "Missing main target context for SDK packing: ${main_context}"
    [[ -f "${manifest_path}" ]] || fail "Missing staged SDK manifest for packing: ${manifest_path}"
    [[ -d "${legal_info_dir}" ]] || fail "Missing staged legal-info directory for packing: ${legal_info_dir}"
    [[ -d "${source_host}" ]] || fail "Missing main target host directory for SDK packing: ${source_host}"
    [[ -d "${source_images}" ]] || fail "Missing main target images directory for SDK packing: ${source_images}"
    [[ -e "${source_staging}" ]] || fail "Missing main target staging path for SDK packing: ${source_staging}"
    [[ -d "${source_motherlode}" ]] || fail "Missing motherlode for SDK packing: ${source_motherlode}"

    rm -rf \
        "${sdk_dir}/alloy" \
        "${sdk_dir}/scripts" \
        "${sdk_dir}/host" \
        "${sdk_dir}/images" \
        "${sdk_dir}/staging" \
        "${sdk_dir}/motherlode" \
        "${sdk_dir}/.alloy_relocation_manifest" \
        "${sdk_dir}/.alloy_sdk_dir"
    mkdir -p "${sdk_dir}"

    cp "${alloy_root}/alloy" "${sdk_dir}/alloy"
    chmod +x "${sdk_dir}/alloy"

    mkdir -p "${sdk_dir}/scripts"
    cp "${alloy_root}/scripts/argparse.sh" "${sdk_dir}/scripts/argparse.sh"
    progress_copy_with_exclusions "copying sdk scripts/commands" "${alloy_root}/scripts/commands" "${sdk_dir}/scripts/commands"
    progress_copy_with_exclusions "copying sdk scripts/utils" "${alloy_root}/scripts/utils" "${sdk_dir}/scripts/utils"
    progress_copy_with_exclusions "copying sdk scripts/tools" "${alloy_root}/scripts/tools" "${sdk_dir}/scripts/tools"
    progress_copy_with_exclusions "copying sdk scripts/plugins" "${alloy_root}/scripts/plugins" "${sdk_dir}/scripts/plugins"
    progress_copy_with_exclusions "copying sdk scripts/buildroot" "${alloy_root}/scripts/buildroot" "${sdk_dir}/scripts/buildroot"
    cp "${main_context}" "${sdk_dir}/scripts/alloy_context.sh"
    # ALLOY_SDK_MANIFEST and legal-info are already generated in staging by the
    # main consolidation pass and serve as authoritative pack inputs.
    [[ -s "${sdk_dir}/ALLOY_SDK_MANIFEST" ]] || fail "Missing staged SDK manifest for packing: ${sdk_dir}/ALLOY_SDK_MANIFEST"
    [[ -d "${sdk_dir}/legal-info" ]] || fail "Missing staged legal-info for packing: ${sdk_dir}/legal-info"
    progress_copy_with_exclusions "copying sdk images" "${source_images}" "${sdk_dir}/images"
    progress_copy_with_exclusions "copying sdk host tools" "${source_host}" "${sdk_dir}/host"
    progress_copy_with_exclusions "copying sdk motherlode" "${source_motherlode}" "${sdk_dir}/motherlode"

    if [[ -L "${source_staging}" ]]; then
        local staging_link_target staging_real staging_rel
        staging_link_target="$(readlink "${source_staging}")"
        if [[ "${staging_link_target}" == /* ]]; then
            staging_real="$(normalize_path "${staging_link_target}")"
        else
            staging_real="$(normalize_path "$(dirname "${source_staging}")/${staging_link_target}")"
        fi
        [[ -d "${staging_real}" ]] || fail "Main target staging symlink target does not exist: ${staging_real}"
        staging_rel="$(relative_path "${main_workspace}" "${staging_real}")"
        progress_copy_with_exclusions "copying sdk staging tree" "${staging_real}" "${sdk_dir}/${staging_rel}"
        ln -sfn "${staging_rel}" "${sdk_dir}/staging"
    else
        progress_copy_with_exclusions "copying sdk staging tree" "${source_staging}" "${sdk_dir}/staging"
    fi

    verify_elf_rpaths "${sdk_dir}"
    sdk_utils_sanitize_text_paths "${sdk_dir}" "${source_host}" "${source_images}" "${source_motherlode}"
    local product_version host_arch archive_name archive_path
    product_version="$(sdk_utils_manifest_product_version "${manifest_path}")"
    host_arch="$(uname -m)"
    archive_name="sdk-${product_id}-${product_version}-${host_arch}.tar.gz"
    archive_path="${ALLOY_ARTEFACT_DIR}/sdk/${archive_name}"
    mkdir -p "$(dirname "${archive_path}")"
    local bundle_root
    bundle_root="sdk-${product_id}-${product_version}-${host_arch}"
    local -a tar_entries=(
        alloy
        scripts
        host
        images
        staging
        motherlode
        legal-info
        ALLOY_SDK_MANIFEST
        .alloy_relocation_manifest
        .alloy_sdk_dir
    )
    if [[ -d "${sdk_dir}/auxiliary" ]]; then
        tar_entries+=(auxiliary)
    fi
    tar -czf "${archive_path}" -C "${sdk_dir}" \
        --transform "flags=r;s,^,${bundle_root}/," \
        "${tar_entries[@]}"
    printf '%s\n' "${archive_path}"
}
