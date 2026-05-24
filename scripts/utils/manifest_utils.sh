#!/usr/bin/env bash

if [[ "${__ALLOY_MANIFEST_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_MANIFEST_UTILS_SH_LOADED=1

MANIFEST_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${MANIFEST_UTILS_DIR}/common.sh"

manifest_utils_fallback_get_field() {
    local manifest_path="$1"
    local field_name="$2"
    local value

    value="$(sed -n "s/.*{${field_name},[[:space:]]*<<\"\\([^\"]*\\)\">>}.*/\\1/p" "${manifest_path}" | head -n 1)"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value}"
        return 0
    fi

    value="$(sed -n "s/.*{${field_name},[[:space:]]*\\([a-zA-Z0-9_@.-]*\\)}.*/\\1/p" "${manifest_path}" | head -n 1)"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value}"
        return 0
    fi

    return 1
}

# manifest_utils_get_field MANIFEST_PATH FIELD_NAME
# Read one top-level manifest field using manifest-tool when available, with a minimal parser fallback.
manifest_utils_get_field() {
    local manifest_path="${1:-}"
    local field_name="${2:-}"
    [[ -n "${manifest_path}" ]] || fail "manifest_utils_get_field requires MANIFEST_PATH"
    [[ -n "${field_name}" ]] || fail "manifest_utils_get_field requires FIELD_NAME"
    [[ -f "${manifest_path}" ]] || fail "Manifest file not found: ${manifest_path}"

    local manifest_tool="${MANIFEST_UTILS_DIR}/../tools/manifest-tool"
    if [[ -x "${manifest_tool}" ]]; then
        local output=""
        if output="$("${manifest_tool}" get --manifest "${manifest_path}" --field "${field_name}" 2>/dev/null)"; then
            printf '%s\n' "${output}"
            return 0
        fi
    fi

    manifest_utils_fallback_get_field "${manifest_path}" "${field_name}"
}
