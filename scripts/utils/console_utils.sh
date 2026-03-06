#!/usr/bin/env bash

if [[ "${__ALLOY_CONSOLE_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_CONSOLE_UTILS_SH_LOADED=1

console_supports_color() {
    local stream="${1:-stdout}"
    local fd
    case "${stream}" in
        stdout|1) fd=1 ;;
        stderr|2) fd=2 ;;
        *) return 1 ;;
    esac

    [[ -z "${NO_COLOR:-}" ]] || return 1
    [[ -t "${fd}" ]]
}

console_style_color_code() {
    case "${1:-}" in
        result) echo "32" ;;
        note|info) echo "36" ;;
        hint|warn) echo "33" ;;
        error) echo "31" ;;
        debug) echo "90" ;;
        *) return 1 ;;
    esac
}

console_format_text() {
    local stream="${1:-stdout}"
    local style="${2:-}"
    shift 2 || true
    local text="$*"

    local color_code
    if color_code="$(console_style_color_code "${style}")" \
        && console_supports_color "${stream}"; then
        printf '\033[%sm%s\033[0m' "${color_code}" "${text}"
        return 0
    fi
    printf '%s' "${text}"
}

console_print_to() {
    local stream="${1:-stdout}"
    local style="${2:-}"
    shift 2 || true

    local formatted
    formatted="$(console_format_text "${stream}" "${style}" "$*")"

    case "${stream}" in
        stderr|2) printf '%s\n' "${formatted}" >&2 ;;
        stdout|1) printf '%s\n' "${formatted}" ;;
        *) return 2 ;;
    esac
}

print_result() {
    console_print_to stdout result "$*"
}

print_note() {
    console_print_to stdout note "$*"
}

print_hint() {
    console_print_to stdout hint "$*"
}
