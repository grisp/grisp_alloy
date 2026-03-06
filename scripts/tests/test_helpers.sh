#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

test_tests_repo_root_points_to_repository_root() {
    local expected_root
    expected_root="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    local actual_root
    actual_root="$(harness_repo_root)"
    assert_equals "${expected_root}" "${actual_root}"
}

test_tests_fixture_path_resolves_relative_paths() {
    local actual
    actual="$(harness_fixture_path "fixture_marker.txt")"
    local expected
    expected="$(harness_fixture_dir)/fixture_marker.txt"
    assert_equals "${expected}" "${actual}"
}

test_tests_discover_shell_tests_lists_bootstrap_tests() {
    local discovered
    discovered="$(harness_discover_shell_tests "$(harness_repo_root)")"
    assert_matches "scripts/tests/test_helpers.sh" "${discovered}"
}

test_tests_require_command_fails_for_unknown_commands() {
    assert_status_code 127 "harness_require_command definitely-not-a-real-command"
}
