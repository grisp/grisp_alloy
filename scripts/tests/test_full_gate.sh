#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

full_gate_test_make_repo() {
    local temp_dir="$1"
    local repo_root
    repo_root="$(harness_repo_root)"

    git init -q "${temp_dir}"
    mkdir -p "${temp_dir}/scripts/tests/gates"
    cp "${repo_root}/scripts/tests/gates/full.sh" "${temp_dir}/scripts/tests/gates/full.sh"
    chmod +x "${temp_dir}/scripts/tests/gates/full.sh"

    cat > "${temp_dir}/scripts/tests/gates/baseline.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "BASELINE"
EOF
    chmod +x "${temp_dir}/scripts/tests/gates/baseline.sh"

    cat > "${temp_dir}/scripts/tests/check_shell_lint.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "SHELL_LINT"
EOF
    chmod +x "${temp_dir}/scripts/tests/check_shell_lint.sh"
}

full_gate_test_make_fake_git() {
    local temp_dir="$1"
    local bin_dir="${temp_dir}/bin"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ge 2 ]] &&
    [[ "$1" == "rev-parse" ]] &&
    [[ "$2" == "--show-toplevel" ]]; then
    if [[ -d .git ]]; then
        pwd -P
        exit 0
    fi
    exit 128
fi

if [[ "$#" -ge 4 ]] &&
    [[ "$1" == "submodule" ]] &&
    [[ "$2" == "sync" ]] &&
    [[ "$3" == "--recursive" ]]; then
    exit 0
fi

if [[ "$#" -ge 4 ]] &&
    [[ "$1" == "submodule" ]] &&
    [[ "$2" == "update" ]] &&
    [[ "$3" == "--init" ]]; then
    repo_root="${FAKE_SUBMODULE_ROOT:?}"
    mkdir -p "${repo_root}/smelterl/scripts/tests" "${repo_root}/smelterl/src"
    : > "${repo_root}/smelterl/rebar.config"
    : > "${repo_root}/smelterl/src/smelterl.app.src"
    cat > "${repo_root}/smelterl/scripts/tests/run_tests.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "SMELTERL_TESTS"
SCRIPT
    chmod +x "${repo_root}/smelterl/scripts/tests/run_tests.sh"
    exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
EOF
    chmod +x "${bin_dir}/git"
    echo "${bin_dir}"
}

test_full_gate_reports_hint_when_smelterl_checkout_is_missing() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "alloy-full-gate")"
    full_gate_test_make_repo "${temp_dir}"

    cat > "${temp_dir}/.gitmodules" <<'EOF'
[submodule "smelterl"]
	path = smelterl
	url = git@github.com:grisp/smelter.git
	branch = main
EOF

    local output
    output="$(ALLOY_INIT_SMELTERL_SUBMODULE=0 \
        "${temp_dir}/scripts/tests/gates/full.sh" 2>&1)"

    assert_matches "BASELINE" "${output}"
    assert_matches "SHELL_LINT" "${output}"
    assert_matches "SKIP: Smelterl test runner not found" "${output}"
    assert_matches "git submodule sync --recursive smelterl" "${output}"
    assert_matches "git submodule update --init --recursive smelterl" "${output}"
}

test_full_gate_can_initialize_smelterl_submodule_on_demand() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "alloy-full-gate")"
    full_gate_test_make_repo "${temp_dir}"
    local fake_git_dir
    fake_git_dir="$(full_gate_test_make_fake_git "${temp_dir}")"

    cat > "${temp_dir}/.gitmodules" <<'EOF'
[submodule "smelterl"]
	path = smelterl
	url = git@github.com:grisp/smelter.git
	branch = main
EOF

    local output
    output="$(PATH="${fake_git_dir}:${PATH}" FAKE_SUBMODULE_ROOT="${temp_dir}" \
        ALLOY_INIT_SMELTERL_SUBMODULE=1 \
        "${temp_dir}/scripts/tests/gates/full.sh" 2>&1)"

    assert_matches "INFO: initializing Smelterl submodule checkout" "${output}"
    assert_matches "SMELTERL_TESTS" "${output}"
}
