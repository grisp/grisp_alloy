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
