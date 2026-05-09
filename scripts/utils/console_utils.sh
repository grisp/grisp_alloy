#!/usr/bin/env bash

if [[ "${__ALLOY_CONSOLE_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_CONSOLE_UTILS_SH_LOADED=1

console_log_prefix() {
    local prefix="${ALLOY_LOG_PREFIX:-}"
    if [[ -n "${prefix}" ]]; then
        printf '[%s] ' "${prefix}"
    fi
}

# console_supports_color [stdout|stderr|1|2]
# Return 0 when the selected stream is a TTY and NO_COLOR is not set.
# Env/side effects: reads NO_COLOR and TTY state; no stdout output, no exports.
# Errors: returns 1 for unsupported stream names or when color should not be used.
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

# console_style_color_code STYLE
# Print the ANSI color code for STYLE on stdout.
# Env/side effects: none.
# Errors: returns 1 when STYLE has no defined color mapping.
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

# console_format_text STREAM STYLE TEXT...
# Format TEXT for STREAM using STYLE and print the result to stdout without a newline.
# Env/side effects: reads NO_COLOR and TTY state through console_supports_color; no exports.
# Errors: falls back to plain text when color is unavailable; only returns non-zero if STYLE lookup fails unexpectedly.
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

# console_print_to STREAM STYLE TEXT...
# Print TEXT plus newline to stdout or stderr, applying STYLE when terminal color is allowed.
# Env/side effects: writes to the selected stream; does not mutate shell state.
# Errors: returns 2 for unsupported stream names; otherwise propagates formatting failures.
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

# print_result TEXT...
# Print a success/result-oriented message to stdout.
# Env/side effects: writes to stdout; style selection is delegated to console_print_to.
# Errors: propagates console_print_to return codes.
print_result() {
    console_print_to stdout result "$(console_log_prefix)$*"
}

# print_note TEXT...
# Print an informational note to stdout.
# Env/side effects: writes to stdout; no exports.
# Errors: propagates console_print_to return codes.
print_note() {
    console_print_to stdout note "$(console_log_prefix)$*"
}

# print_hint TEXT...
# Print a hint or follow-up suggestion to stdout.
# Env/side effects: writes to stdout; no exports.
# Errors: propagates console_print_to return codes.
print_hint() {
    console_print_to stdout hint "$(console_log_prefix)$*"
}
