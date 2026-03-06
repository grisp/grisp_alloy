#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

alloy_test_make_command_handlers() {
    local command_dir="$1"
    mkdir -p "${command_dir}"

    cat > "${command_dir}/build-sdk.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "HANDLER=build-sdk"
echo "ALLOY_MODE=${ALLOY_MODE:-}"
echo "ALLOY_DEBUG=${ALLOY_DEBUG:-}"
echo "ALLOY_TRACE=${ALLOY_TRACE:-}"
echo "ALLOY_DEV_MODE=${ALLOY_DEV_MODE:-}"
echo "ALLOY_FORCE_VAGRANT=${ALLOY_FORCE_VAGRANT:-}"
echo "ALLOY_KEEP_VAGRANT=${ALLOY_KEEP_VAGRANT:-}"
echo "ALLOY_PROVISION=${ALLOY_PROVISION:-}"
echo "ALLOY_FORWARD_ENV=${ALLOY_FORWARD_ENV:-}"
printf "ARGS:"
for arg in "$@"; do
    printf " <%s>" "$arg"
done
printf "\n"
EOF

    cat > "${command_dir}/ping.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "HANDLER=ping"
printf "ARGS:"
for arg in "$@"; do
    printf " <%s>" "$arg"
done
printf "\n"
EOF

    chmod +x "${command_dir}/build-sdk.sh" "${command_dir}/ping.sh"
}

test_alloy_version_flag_returns_success() {
    local alloy
    alloy="$(harness_repo_root)/alloy"
    assert_status_code 0 "\"${alloy}\" --version"
}

test_alloy_help_flag_shows_global_usage() {
    local alloy
    alloy="$(harness_repo_root)/alloy"
    local output
    output="$("${alloy}" --help 2>&1)"
    assert_matches "Usage: alloy" "${output}"
}

test_alloy_unknown_global_option_before_command_fails() {
    local alloy
    alloy="$(harness_repo_root)/alloy"
    assert_status_code 2 "\"${alloy}\" --unknown-global build sdk"
}

test_alloy_dispatches_verb_noun_with_normalized_global_env() {
    local alloy
    alloy="$(harness_repo_root)/alloy"
    local temp_dir
    temp_dir="$(harness_make_temp_dir "alloy-entry")"
    local command_dir="${temp_dir}/commands"
    alloy_test_make_command_handlers "${command_dir}"

    local output
    output="$(ALLOY_COMMANDS_DIR="${command_dir}" \
        "${alloy}" build --trace sdk -dd --dev -F -K -P \
        --forward-env SIGNING_* alpha --beta 2>&1)"

    assert_matches "HANDLER=build-sdk" "${output}"
    assert_matches "ALLOY_DEBUG=2" "${output}"
    assert_matches "ALLOY_TRACE=true" "${output}"
    assert_matches "ALLOY_DEV_MODE=true" "${output}"
    assert_matches "ALLOY_FORCE_VAGRANT=true" "${output}"
    assert_matches "ALLOY_KEEP_VAGRANT=true" "${output}"
    assert_matches "ALLOY_PROVISION=true" "${output}"
    assert_matches "ALLOY_FORWARD_ENV=SIGNING_\\*" "${output}"
    assert_matches "ARGS: <alpha> <--beta>" "${output}"
}

test_alloy_keeps_command_options_after_verb_noun() {
    local alloy
    alloy="$(harness_repo_root)/alloy"
    local temp_dir
    temp_dir="$(harness_make_temp_dir "alloy-entry")"
    local command_dir="${temp_dir}/commands"
    alloy_test_make_command_handlers "${command_dir}"

    local output
    output="$(ALLOY_COMMANDS_DIR="${command_dir}" \
        "${alloy}" build sdk --unknown-opt value 2>&1)"
    assert_matches "ARGS: <--unknown-opt> <value>" "${output}"
}

test_alloy_dispatches_single_word_command_handler() {
    local alloy
    alloy="$(harness_repo_root)/alloy"
    local temp_dir
    temp_dir="$(harness_make_temp_dir "alloy-entry")"
    local command_dir="${temp_dir}/commands"
    alloy_test_make_command_handlers "${command_dir}"

    local output
    output="$(ALLOY_COMMANDS_DIR="${command_dir}" "${alloy}" ping pong 2>&1)"
    assert_matches "HANDLER=ping" "${output}"
    assert_matches "ARGS: <pong>" "${output}"
}

test_alloy_forwards_help_to_command_handler_when_command_is_present() {
    local alloy
    alloy="$(harness_repo_root)/alloy"
    local temp_dir
    temp_dir="$(harness_make_temp_dir "alloy-entry")"
    local command_dir="${temp_dir}/commands"
    alloy_test_make_command_handlers "${command_dir}"

    local output
    output="$(ALLOY_COMMANDS_DIR="${command_dir}" "${alloy}" build sdk --help 2>&1)"
    assert_matches "ARGS: <--help>" "${output}"
}
