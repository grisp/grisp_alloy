#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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
    echo "ERROR: No shell files found to check" >&2
    exit 1
fi

for shell_file in "${shell_files[@]}"; do
    bash -n "${shell_file}"
done
