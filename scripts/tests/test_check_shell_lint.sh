#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

test_shell_lint_checker_runs_with_default_policy() {
    local lint_checker
    lint_checker="$(harness_repo_root)/scripts/tests/check_shell_lint.sh"
    assert_status_code 0 "ALLOY_REQUIRE_SHELLCHECK=0 \"${lint_checker}\""
}
