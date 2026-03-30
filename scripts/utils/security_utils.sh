#!/usr/bin/env bash

if [[ "${__ALLOY_SECURITY_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_SECURITY_UTILS_SH_LOADED=1

SECURITY_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${SECURITY_UTILS_DIR}/common.sh"

security__require_configured_pack() {
    if [[ -z "${ALLOY_SECURITY_PACK:-}" ]]; then
        log_error "No security pack configured. Use --security-pack or set ALLOY_SECURITY_PACK."
        return 1
    fi

    if [[ ! -f "${ALLOY_SECURITY_PACK}" ]] || [[ ! -x "${ALLOY_SECURITY_PACK}" ]]; then
        log_error "Security pack is not executable: ${ALLOY_SECURITY_PACK}"
        return 1
    fi
}

security__emit_filtered_kv_output() {
    local output="${1-}"
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" ]] || continue
        [[ "${line}" == *=* ]] || continue
        printf '%s\n' "${line}"
    done <<< "${output}"
}

security__run_kv_command() {
    local command_name="${1:-}"
    shift || true

    security__require_configured_pack || return $?
    require_command mktemp || return $?

    local stderr_file
    stderr_file="$(mktemp "${TMPDIR:-/tmp}/alloy-security-utils.XXXXXX")" || return 1

    local output rc stderr_output
    output="$("${ALLOY_SECURITY_PACK}" "${command_name}" "$@" 2>"${stderr_file}")"
    rc=$?
    stderr_output=""
    if [[ -f "${stderr_file}" ]]; then
        stderr_output="$(<"${stderr_file}")"
        rm -f "${stderr_file}"
    fi

    if [[ ${rc} -ne 0 ]]; then
        if [[ -n "${stderr_output}" ]]; then
            printf '%s\n' "${stderr_output}" >&2
        fi
        return ${rc}
    fi

    security_validate_kv_output "${command_name}" "${output}" || return $?
    security__emit_filtered_kv_output "${output}"
}

# security_resolve_pack VALUE
# Resolve VALUE to an absolute security-pack entrypoint path after validating the supported file/directory forms and a working `capabilities` command.
# Env/side effects: reads PATH for `realpath`; invokes the candidate pack's `capabilities` subcommand; prints the resolved absolute executable path to stdout.
# Errors: returns 2 for missing arguments or missing `realpath`, 1 for unsupported/broken pack paths, and logs design-defined validation failures.
security_resolve_pack() {
    local value="${1:-}"
    if [[ -z "${value}" ]]; then
        log_error "security_resolve_pack requires VALUE"
        return 2
    fi

    require_command realpath || return $?

    if [[ "${value}" != */* ]]; then
        log_error "Security pack not found: ${value}"
        return 1
    fi

    local resolved
    if [[ -d "${value}" ]]; then
        resolved="${value}/secpack"
        if [[ ! -f "${resolved}" ]] || [[ ! -x "${resolved}" ]]; then
            log_error "Security pack directory '${value}' does not contain a 'secpack' executable at its root."
            return 1
        fi
    elif [[ -f "${value}" ]]; then
        if [[ ! -x "${value}" ]]; then
            log_error "Security pack is not executable: ${value}"
            return 1
        fi
        resolved="${value}"
    else
        log_error "Security pack not found: ${value}"
        return 1
    fi

    local capabilities_output
    if ! capabilities_output="$("${resolved}" capabilities 2>/dev/null)"; then
        log_error "'${resolved}' does not appear to be a valid security pack (capabilities command failed)."
        return 1
    fi

    if [[ -z "${capabilities_output}" ]]; then
        log_error "'${resolved}' does not appear to be a valid security pack (capabilities command failed)."
        return 1
    fi

    realpath "${resolved}"
}

# security_generate_overlay OUTPUT_DIR [EXTRA_ARGS...]
# Invoke the configured security pack's `generate-overlay` command to write rootfs overlay content into OUTPUT_DIR.
# Env/side effects: requires `ALLOY_SECURITY_PACK`; executes the pack in the current environment; stdout/stderr pass through from the pack.
# Errors: returns 2 when OUTPUT_DIR is omitted, 1 for missing/non-executable pack or missing OUTPUT_DIR, and otherwise propagates the pack's exit status (including exit 2 for unsupported overlays).
security_generate_overlay() {
    local output_dir="${1:-}"
    shift || true

    if [[ -z "${output_dir}" ]]; then
        log_error "security_generate_overlay requires OUTPUT_DIR"
        return 2
    fi

    if [[ ! -d "${output_dir}" ]]; then
        log_error "Security overlay output directory not found: ${output_dir}"
        return 1
    fi

    security__require_configured_pack || return $?
    "${ALLOY_SECURITY_PACK}" generate-overlay "${output_dir}" "$@"
}

# security_info
# Print validated `key=value` metadata from the configured security pack's `info` command for manifest assembly.
# Env/side effects: requires `ALLOY_SECURITY_PACK`; invokes the pack and filters stdout down to validated key=value lines.
# Errors: returns 1 for missing/invalid pack configuration or invalid key output, 2/3 when the pack reports those statuses, and otherwise preserves pack stderr on failures.
security_info() {
    security__run_kv_command "info"
}

# security_export_env
# Print validated `key=value` pairs from the configured security pack's `env` command for later export as `ALLOY_SECURITY_*`.
# Env/side effects: requires `ALLOY_SECURITY_PACK`; invokes the pack and filters stdout down to validated key=value lines.
# Errors: returns 1 for missing/invalid pack configuration or invalid key output, 2/3 when the pack reports those statuses, and otherwise preserves pack stderr on failures.
security_export_env() {
    security__run_kv_command "env"
}

# security_validate_kv_output COMMAND OUTPUT
# Validate COMMAND stdout as security-pack `key=value` output by rejecting invalid keys and tolerating blank/non-pair lines.
# Env/side effects: none.
# Errors: returns 2 when COMMAND/OUTPUT arguments are missing, 1 for invalid keys with a contextual error message, and 0 otherwise.
security_validate_kv_output() {
    if [[ $# -lt 2 ]]; then
        log_error "security_validate_kv_output requires COMMAND and OUTPUT"
        return 2
    fi

    local command_name="$1"
    local output="$2"
    local line key
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" ]] || continue
        [[ "${line}" == *=* ]] || continue
        key="${line%%=*}"
        if [[ ! "${key}" =~ ^[a-z][a-z0-9_]*$ ]]; then
            log_error "Security pack error: invalid key '${key}' in '${command_name}' output - keys must match [a-z][a-z0-9_]*."
            return 1
        fi
    done <<< "${output}"
}
