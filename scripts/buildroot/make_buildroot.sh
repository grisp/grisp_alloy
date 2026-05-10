#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: make_buildroot.sh [MAKE_ARGS...]

Runs Buildroot make while:
  - appending timestamped full output to br.log in the workspace (O=...),
  - prefixing console output with [buildroot],
  - controlling console verbosity via ALLOY_BUILDROOT_DEBUG.

Environment:
  ALLOY_BUILDROOT_DEBUG=0   Reduced console output (progress lines only), no V=1.
  ALLOY_BUILDROOT_DEBUG=1   Full console output, no V=1.
  ALLOY_BUILDROOT_DEBUG=2+  Full console output, add V=1.
USAGE
}

is_non_negative_integer() {
    local value="${1:-}"
    [[ "${value}" =~ ^[0-9]+$ ]]
}

extract_workspace_dir() {
    local arg
    for arg in "$@"; do
        if [[ "${arg}" == O=* ]]; then
            printf '%s\n' "${arg#O=}"
            return 0
        fi
    done
    return 1
}

strip_ansi() {
    sed -E $'s/\x1B\[[0-9;]*[[:alpha:]]//g'
}

supports_ansi() {
    [[ -z "${NO_COLOR:-}" ]] || return 1
    [[ -t 1 ]] || return 1
    [[ "${TERM:-}" != "dumb" ]] || return 1
    if command -v tput >/dev/null 2>&1; then
        local colors
        if colors="$(tput colors 2>/dev/null)" && [[ "${colors}" =~ ^[0-9]+$ ]]; then
            (( colors >= 8 )) || return 1
        fi
    fi
    return 0
}

main() {
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    local buildroot_debug="${ALLOY_BUILDROOT_DEBUG:-0}"
    is_non_negative_integer "${buildroot_debug}" ||
        {
            printf '[buildroot] ERROR: ALLOY_BUILDROOT_DEBUG must be a non-negative integer, got: %s\n' "${buildroot_debug}" >&2
            exit 2
        }

    local workspace_dir
    workspace_dir="$(extract_workspace_dir "$@")" ||
        {
            printf '[buildroot] ERROR: missing required make argument O=<workspace-dir>\n' >&2
            exit 2
        }
    mkdir -p "${workspace_dir}"

    local log_file="${workspace_dir}/br.log"
    local -a make_cmd=(make "$@")
    if (( buildroot_debug >= 2 )); then
        make_cmd+=("V=1")
    fi
    if supports_ansi; then
        make_cmd+=("ALLOY_FORCE_COLOR=1")
    fi

    local status_file
    status_file="$(mktemp)"

    local prefix='[buildroot]'
    local spinner_enabled=false
    local spinner_drawn=false
    local spinner_index=0
    local -a spinner_frames=('|' '/' '-' '\')
    local cursor_hidden=false
    cleanup() {
        if [[ "${spinner_drawn}" == true ]]; then
            printf '\r\033[K'
        fi
        if [[ "${cursor_hidden}" == true ]]; then
            tput cnorm >/dev/null 2>&1 || true
        fi
    }
    trap cleanup EXIT

    if (( buildroot_debug == 0 )) && supports_ansi; then
        spinner_enabled=true
        prefix=$'\033[34m[buildroot]\033[0m'
        if command -v tput >/dev/null 2>&1; then
            if tput civis >/dev/null 2>&1; then
                cursor_hidden=true
            fi
        fi
    fi

    while IFS= read -r line; do
        local log_ts
        printf -v log_ts "%(%Y-%m-%dT%H:%M:%S)T" -1
        if [[ -z "${NO_COLOR:-}" ]]; then
            printf '\033[34m%s\033[0m | %s\n' "${log_ts}" "${line}" >> "${log_file}"
        else
            printf '%s | %s\n' "${log_ts}" "${line}" >> "${log_file}"
        fi

        local plain_line
        plain_line="$(printf '%s\n' "${line}" | strip_ansi)"

        if (( buildroot_debug == 0 )); then
            if ! [[ "${plain_line}" =~ ^\>\>\>[[:space:]] ]] &&
                ! [[ "${plain_line}" =~ ^\[alloy([^]]*)\] ]]; then
                if [[ "${spinner_enabled}" == true ]]; then
                    local frame="${spinner_frames[$spinner_index]}"
                    printf '\r%s %s' "${prefix}" "${frame}"
                    spinner_drawn=true
                    spinner_index=$(((spinner_index + 1) % ${#spinner_frames[@]}))
                fi
                continue
            fi
        fi

        if [[ "${spinner_drawn}" == true ]]; then
            printf '\r\033[K'
            spinner_drawn=false
        fi

        local emitted_line="${line}"
        if [[ "${plain_line}" =~ ^\>\>\>[[:space:]] ]]; then
            emitted_line="$(printf '%s\n' "${plain_line}" | sed -E 's/^[[:space:]]*>>>[[:space:]]+//')"
        elif (( buildroot_debug == 0 )) && ! [[ "${plain_line}" =~ ^\[alloy([^]]*)\] ]]; then
            emitted_line="${plain_line}"
        fi

        printf '%s %s\n' "${prefix}" "${emitted_line}"
    done < <(
        set +e
        "${make_cmd[@]}" 2>&1
        printf '%s\n' "$?" > "${status_file}"
    )

    local ret=0
    if [[ -s "${status_file}" ]]; then
        ret="$(cat "${status_file}")"
    fi
    rm -f "${status_file}"

    exit "${ret}"
}

main "$@"
