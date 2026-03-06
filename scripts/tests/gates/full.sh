#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

require_smelterl_tests="${ALLOY_REQUIRE_SMELTERL_TESTS:-0}"
smelterl_runner="${REPO_ROOT}/smelterl/scripts/tests/run_tests.sh"
smelterl_dir="${REPO_ROOT}/smelterl"

"${REPO_ROOT}/scripts/tests/gates/baseline.sh"
"${REPO_ROOT}/scripts/tests/check_shell_lint.sh"

if [[ -x "${smelterl_runner}" ]]; then
    "${smelterl_runner}" "$@"
elif [[ -d "${smelterl_dir}" && -f "${smelterl_dir}/rebar.config" ]]; then
    if ! command -v rebar3 >/dev/null 2>&1; then
        if [[ "${require_smelterl_tests}" == "1" ]]; then
            echo "ERROR: rebar3 is required for Smelterl tests but not available on PATH" >&2
            exit 127
        fi
        echo "SKIP: rebar3 not found on PATH; skipping Smelterl tests" >&2
        exit 0
    fi
    (
        cd "${smelterl_dir}"
        rebar3 as test ct "$@"
    )
else
    if [[ "${require_smelterl_tests}" == "1" ]]; then
        echo "ERROR: Smelterl test runner not found at ${smelterl_runner}" >&2
        exit 2
    fi
    echo "SKIP: Smelterl test runner not found at ${smelterl_runner}" >&2
fi
