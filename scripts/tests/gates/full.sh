#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

require_smelterl_tests="${ALLOY_REQUIRE_SMELTERL_TESTS:-0}"
init_smelterl_submodule="${ALLOY_INIT_SMELTERL_SUBMODULE:-0}"
smelterl_runner="${REPO_ROOT}/smelterl/scripts/tests/run_tests.sh"
smelterl_dir="${REPO_ROOT}/smelterl"
smelterl_hint="git submodule sync --recursive smelterl && git submodule update --init --recursive smelterl"

repo_declares_smelterl_submodule() {
    local gitmodules_path="${REPO_ROOT}/.gitmodules"
    [[ -f "${gitmodules_path}" ]] || return 1
    grep -Fq '[submodule "smelterl"]' "${gitmodules_path}" &&
        grep -Fq 'path = smelterl' "${gitmodules_path}"
}

smelterl_checkout_ready() {
    [[ -x "${smelterl_runner}" ]] ||
        ([[ -d "${smelterl_dir}" ]] && [[ -f "${smelterl_dir}/rebar.config" ]])
}

maybe_init_smelterl_submodule() {
    [[ "${init_smelterl_submodule}" == "1" ]] || return 0
    smelterl_checkout_ready && return 0

    if ! repo_declares_smelterl_submodule; then
        echo "SKIP: Smelterl checkout missing and no smelterl submodule is configured" >&2
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        if [[ "${require_smelterl_tests}" == "1" ]]; then
            echo "ERROR: git is required to initialize the Smelterl submodule" >&2
            exit 127
        fi
        echo "SKIP: git not found on PATH; cannot initialize Smelterl submodule" >&2
        return 0
    fi

    if ! (
        cd "${REPO_ROOT}"
        git rev-parse --show-toplevel >/dev/null 2>&1
    ); then
        if [[ "${require_smelterl_tests}" == "1" ]]; then
            echo "ERROR: ${REPO_ROOT} is not a git checkout; cannot initialize the Smelterl submodule" >&2
            exit 2
        fi
        echo "SKIP: ${REPO_ROOT} is not a git checkout; cannot initialize Smelterl submodule" >&2
        return 0
    fi

    echo "INFO: initializing Smelterl submodule checkout..." >&2
    (
        cd "${REPO_ROOT}"
        git submodule sync --recursive smelterl
        git submodule update --init --recursive smelterl
    )
}

"${REPO_ROOT}/scripts/tests/gates/baseline.sh"
"${REPO_ROOT}/scripts/tests/check_shell_lint.sh"
maybe_init_smelterl_submodule

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
        echo "HINT: run '${smelterl_hint}' or set ALLOY_INIT_SMELTERL_SUBMODULE=1" >&2
        exit 2
    fi
    echo "SKIP: Smelterl test runner not found at ${smelterl_runner}" >&2
    echo "HINT: run '${smelterl_hint}' or set ALLOY_INIT_SMELTERL_SUBMODULE=1" >&2
fi
