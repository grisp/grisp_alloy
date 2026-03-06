#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

test_shell_syntax_checker_succeeds_for_repository_scripts() {
    local syntax_checker
    syntax_checker="$(harness_repo_root)/scripts/tests/check_shell_syntax.sh"
    assert_status_code 0 "\"${syntax_checker}\""
}
