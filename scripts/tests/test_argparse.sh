#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

ARGPARSE_SCRIPT="$(harness_repo_root)/scripts/argparse.sh"
# shellcheck source=scripts/argparse.sh
source "${ARGPARSE_SCRIPT}"

argparse_test_reset() {
    args_init
    unset ARG_DEBUG ARG_DEBUG_OPT ARG_VERBOSE ARG_VERBOSE_OPT ARG_OPT ARG_OPT_OPT
    unset ARG_PATHS ARG_PATHS_OPT
    POSITIONAL=()
}

test_argparse_count_defaults_to_zero_when_absent() {
    argparse_test_reset
    args_add d debug ARG_DEBUG count 0

    args_parse

    assert_equals "0" "${ARG_DEBUG}"
    assert_equals "0" "${ARG_DEBUG_OPT}"
    assert_equals "0" "${#POSITIONAL[@]}"
}

test_argparse_count_short_repetition_increments_and_tracks_occurrences() {
    argparse_test_reset
    args_add d debug ARG_DEBUG count 0

    args_parse -ddd

    assert_equals "3" "${ARG_DEBUG}"
    assert_equals "3" "${ARG_DEBUG_OPT}"
}

test_argparse_count_short_attached_digits_set_value() {
    argparse_test_reset
    args_add d debug ARG_DEBUG count 0

    args_parse -d4

    assert_equals "4" "${ARG_DEBUG}"
    assert_equals "1" "${ARG_DEBUG_OPT}"
}

test_argparse_count_long_forms_increment_then_assign() {
    argparse_test_reset
    args_add d debug ARG_DEBUG count 0

    args_parse --debug --debug=3

    assert_equals "3" "${ARG_DEBUG}"
    assert_equals "2" "${ARG_DEBUG_OPT}"
}

test_argparse_count_long_without_equals_keeps_next_token_positional() {
    argparse_test_reset
    args_add d debug ARG_DEBUG count 0

    args_parse --debug 3 sample

    assert_equals "1" "${ARG_DEBUG}"
    assert_equals "1" "${ARG_DEBUG_OPT}"
    assert_equals "2" "${#POSITIONAL[@]}"
    assert_equals "3" "${POSITIONAL[0]}"
    assert_equals "sample" "${POSITIONAL[1]}"
}

test_argparse_count_combined_short_with_flag_supports_dash_v_d3_form() {
    argparse_test_reset
    args_add v verbose ARG_VERBOSE flag true false
    args_add d debug ARG_DEBUG count 0

    args_parse -vd3

    assert_equals "true" "${ARG_VERBOSE}"
    assert_equals "1" "${ARG_VERBOSE_OPT}"
    assert_equals "3" "${ARG_DEBUG}"
    assert_equals "1" "${ARG_DEBUG_OPT}"
}

test_argparse_count_rejects_invalid_long_value() {
    argparse_test_reset
    args_add d debug ARG_DEBUG count 0

    local output status
    output="$({ args_parse --debug=abc; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "non-negative integer" "${output}"
}

test_argparse_count_rejects_invalid_short_value() {
    argparse_test_reset
    args_add d debug ARG_DEBUG count 0

    local output status
    output="$({ args_parse -d3x; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "non-negative integer" "${output}"
}

test_argparse_keeps_flag_value_and_accum_behavior() {
    argparse_test_reset
    args_add v verbose ARG_VERBOSE flag true false
    args_add o opt ARG_OPT value default
    args_add p path ARG_PATHS accum

    args_parse -v --opt=xyz -pone --path two trailing

    assert_equals "true" "${ARG_VERBOSE}"
    assert_equals "1" "${ARG_VERBOSE_OPT}"
    assert_equals "xyz" "${ARG_OPT}"
    assert_equals "1" "${ARG_OPT_OPT}"
    assert_equals "2" "${ARG_PATHS_OPT}"
    assert_equals "2" "${#ARG_PATHS[@]}"
    assert_equals "one" "${ARG_PATHS[0]}"
    assert_equals "two" "${ARG_PATHS[1]}"
    assert_equals "1" "${#POSITIONAL[@]}"
    assert_equals "trailing" "${POSITIONAL[0]}"
}

test_argparse_value_long_space_form_consumes_next_token() {
    argparse_test_reset
    args_add o opt ARG_OPT value default

    args_parse --opt xyz tail

    assert_equals "xyz" "${ARG_OPT}"
    assert_equals "1" "${ARG_OPT_OPT}"
    assert_equals "1" "${#POSITIONAL[@]}"
    assert_equals "tail" "${POSITIONAL[0]}"
}

test_argparse_double_dash_stops_option_parsing() {
    argparse_test_reset
    args_add o opt ARG_OPT value default

    args_parse --opt before -- --opt after

    assert_equals "before" "${ARG_OPT}"
    assert_equals "1" "${ARG_OPT_OPT}"
    assert_equals "2" "${#POSITIONAL[@]}"
    assert_equals "--opt" "${POSITIONAL[0]}"
    assert_equals "after" "${POSITIONAL[1]}"
}
