#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

require_shellcheck="${ALLOY_REQUIRE_SHELLCHECK:-0}"
strict_shellcheck="${ALLOY_SHELLCHECK_STRICT:-0}"
# TODO(ci-docs): document and enforce ALLOY_SHELLCHECK_STRICT=1 in CI/dev docs once the project process docs are finalized.

if ! command -v shellcheck >/dev/null 2>&1; then
    if [[ "${require_shellcheck}" == "1" ]]; then
        echo "ERROR: shellcheck is required but not available on PATH" >&2
        exit 127
    fi
    echo "SKIP: shellcheck not found on PATH" >&2
    exit 0
fi

declare -a shell_files=()

if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    while IFS= read -r relpath; do
        [[ -n "${relpath}" ]] || continue
        shell_files+=("${REPO_ROOT}/${relpath}")
    done < <(git -C "${REPO_ROOT}" ls-files '*.sh')
else
    while IFS= read -r filepath; do
        shell_files+=("${filepath}")
    done < <(find "${REPO_ROOT}" -type f -name '*.sh' -not -path "${REPO_ROOT}/.git/*" | LC_ALL=C sort)
fi

if [[ ${#shell_files[@]} -eq 0 ]]; then
    echo "ERROR: No shell files found to lint" >&2
    exit 1
fi

tmp_output="$(mktemp "${TMPDIR:-/tmp}/grisp-alloy-shellcheck.XXXXXX")"
trap 'rm -f "${tmp_output}"' EXIT

if shellcheck "${shell_files[@]}" >"${tmp_output}" 2>&1; then
    exit 0
fi

if [[ "${strict_shellcheck}" == "1" ]]; then
    cat "${tmp_output}" >&2
    exit 1
fi

echo "WARN: shellcheck reported findings (non-blocking)." >&2
echo "WARN: set ALLOY_SHELLCHECK_STRICT=1 to make findings fail the gate." >&2
sed -n '1,80p' "${tmp_output}" >&2
exit 0
