#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

SERVE_ARTEFACTS_COMMAND="$(harness_repo_root)/scripts/commands/serve-artefacts.sh"

serve_artefacts_test_make_fixture() {
    local temp_dir="$1"
    local root_dir="${temp_dir}/fixture"
    mkdir -p "${root_dir}/scripts/commands" "${root_dir}/scripts/tools"
    cp "${SERVE_ARTEFACTS_COMMAND}" "${root_dir}/scripts/commands/serve-artefacts.sh"
    chmod +x "${root_dir}/scripts/commands/serve-artefacts.sh"
    cat > "${root_dir}/scripts/tools/artefact-server" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'TOOL=artefact-server\n'
printf 'ARGS:'
for arg in "$@"; do
    printf ' <%s>' "${arg}"
done
printf '\n'
EOF
    chmod +x "${root_dir}/scripts/tools/artefact-server"
    printf '%s\n' "${root_dir}"
}

test_serve_artefacts_command_invokes_scripts_tools_wrapper() {
    local temp_dir root_dir command_path output status
    temp_dir="$(harness_make_temp_dir "serve-artefacts")"
    root_dir="$(serve_artefacts_test_make_fixture "${temp_dir}")"
    command_path="${root_dir}/scripts/commands/serve-artefacts.sh"

    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR "${command_path}" --port 8443 --verbose 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "TOOL=artefact-server" "${output}"
    assert_matches "ARGS: <--port> <8443> <--verbose>" "${output}"
}
