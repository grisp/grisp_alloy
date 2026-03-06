#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

CONSOLE_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/console_utils.sh"
# shellcheck source=scripts/utils/console_utils.sh
source "${CONSOLE_UTILS_SCRIPT}"

test_console_utils_print_helpers_emit_plain_output_by_default() {
    local result_out note_out hint_out
    result_out="$(print_result "build complete")"
    note_out="$(print_note "remember this")"
    hint_out="$(print_hint "try --help")"

    assert_equals "build complete" "${result_out}"
    assert_equals "remember this" "${note_out}"
    assert_equals "try --help" "${hint_out}"
}

test_console_utils_print_helpers_emit_colors_when_supported() {
    local original_supports_color
    original_supports_color="$(declare -f console_supports_color)"
    # shellcheck disable=SC2317
    console_supports_color() { return 0; }

    local result_out note_out hint_out
    result_out="$(print_result "ok")"
    note_out="$(print_note "note")"
    hint_out="$(print_hint "hint")"

    eval "${original_supports_color}"

    assert_equals $'\033[32mok\033[0m' "${result_out}"
    assert_equals $'\033[36mnote\033[0m' "${note_out}"
    assert_equals $'\033[33mhint\033[0m' "${hint_out}"
}

test_console_utils_no_color_disables_ansi_sequences() {
    local original_supports_color
    original_supports_color="$(declare -f console_supports_color)"
    # shellcheck disable=SC2317
    console_supports_color() { [[ -z "${NO_COLOR:-}" ]]; }
    export NO_COLOR=1

    local output
    output="$(print_result "no-color")"

    unset NO_COLOR || true
    eval "${original_supports_color}"

    assert_equals "no-color" "${output}"
}

test_console_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${CONSOLE_UTILS_SCRIPT}\"; source \"${CONSOLE_UTILS_SCRIPT}\"; print_result ok >/dev/null'"
}
