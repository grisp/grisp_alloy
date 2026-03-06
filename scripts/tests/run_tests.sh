#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${REPO_ROOT}/scripts/tests/lib/test_helpers.sh"

harness_require_command bash_unit

declare -a test_files=()
while IFS= read -r test_file; do
    test_files+=("${test_file}")
done < <(harness_discover_shell_tests "${REPO_ROOT}")

if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "ERROR: No shell test files found under ${REPO_ROOT}/scripts/tests" >&2
    exit 1
fi

bash_unit "$@" "${test_files[@]}"
