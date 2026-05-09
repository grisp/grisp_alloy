#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: make_buildroot.sh [MAKE_ARGS...]

Runs Buildroot make while:
  - appending timestamped full output to br.log in the workspace (O=...),
  - prefixing console output with [buildroot],
  - controlling console verbosity via ALLOY_BUILDROOT_DEBUG.

Environment:
  ALLOY_BUILDROOT_DEBUG=0   Reduced console output (progress lines only), no V=1.
  ALLOY_BUILDROOT_DEBUG=1   Full console output, no V=1.
  ALLOY_BUILDROOT_DEBUG=2+  Full console output, add V=1.
EOF
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

    local status_file
    status_file="$(mktemp)"
    (
        set +e
        "${make_cmd[@]}" 2>&1
        printf '%s\n' "$?" > "${status_file}"
    ) | while IFS= read -r line; do

        printf "%(%Y-%m-%dT%H:%M:%S)T %s\n" -1 "${line}" >> "${log_file}"

        if (( buildroot_debug == 0 )); then
            local plain_line
            plain_line="$(printf '%s\n' "${line}" | sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g')"
            if ! [[ "${plain_line}" =~ ^\>\>\>[[:space:]] ]] &&
                ! [[ "${plain_line}" =~ ^\[alloy([^]]*)\] ]]; then
                continue
            fi
        fi
        printf '[buildroot] %s\n' "${line}"
    done

    local ret=0
    if [[ -s "${status_file}" ]]; then
        ret="$(cat "${status_file}")"
    fi
    rm -f "${status_file}"

    exit "${ret}"
}

main "$@"
