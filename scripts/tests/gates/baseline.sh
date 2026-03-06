#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

"${REPO_ROOT}/scripts/tests/check_shell_syntax.sh"
"${REPO_ROOT}/scripts/tests/run_tests.sh"
