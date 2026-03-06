#!/usr/bin/env bash

harness_repo_root() {
    local helper_dir
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    (cd "${helper_dir}/../../.." && pwd)
}

harness_fixture_dir() {
    echo "$(harness_repo_root)/scripts/tests/fixtures"
}

harness_fixture_path() {
    local relative_path="${1:-}"
    if [[ -z "${relative_path}" ]]; then
        echo "ERROR: harness_fixture_path requires a relative path" >&2
        return 2
    fi
    echo "$(harness_fixture_dir)/${relative_path}"
}

harness_make_temp_dir() {
    local prefix="${1:-grisp-alloy-tests}"
    mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

harness_make_temp_file() {
    local prefix="${1:-grisp-alloy-tests}"
    mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

harness_require_command() {
    local command_name="${1:-}"
    if [[ -z "${command_name}" ]]; then
        echo "ERROR: harness_require_command requires a command name" >&2
        return 2
    fi
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: ${command_name}" >&2
        return 127
    fi
}

harness_discover_shell_tests() {
    local repo_root="${1:-$(harness_repo_root)}"
    find "${repo_root}/scripts/tests" \
        -maxdepth 1 \
        -type f \
        -name 'test_*.sh' \
        -print \
        | LC_ALL=C sort
}
