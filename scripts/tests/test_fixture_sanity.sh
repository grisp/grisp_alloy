#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

test_fixture_directory_exists() {
    local fixture_dir
    fixture_dir="$(harness_fixture_dir)"
    assert_status_code 0 "[[ -d \"${fixture_dir}\" ]]"
}

test_marker_fixture_file_exists() {
    local marker_file
    marker_file="$(harness_fixture_path "fixture_marker.txt")"
    assert_status_code 0 "[[ -f \"${marker_file}\" ]]"
}

test_marker_fixture_has_expected_content() {
    local marker_file
    marker_file="$(harness_fixture_path "fixture_marker.txt")"
    local content
    content="$(cat "${marker_file}")"
    assert_equals "grisp-alloy-test-fixture" "${content}"
}
