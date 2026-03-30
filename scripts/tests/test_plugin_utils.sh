#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

PLUGIN_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/plugin_utils.sh"
# shellcheck source=scripts/utils/plugin_utils.sh
source "${PLUGIN_UTILS_SCRIPT}"

plugin_utils_test_make_plugin_dir() {
    local temp_dir="$1"
    local plugin_dir="${temp_dir}/plugins/project"
    mkdir -p "${plugin_dir}"

    cat > "${plugin_dir}/beta.sh" <<'EOF'
printf 'beta\n' >> "${PLUGIN_UTILS_TEST_LOAD_LOG}"
project_beta_detect() { return 0; }
project_beta_build() { printf 'beta-build:%s\n' "$1"; }
project_beta_info() {
    printf 'name=beta\n'
    printf 'version=1.2.3\n'
    printf 'note=contains=equals\n'
    printf 'ignored-line-without-separator\n'
}
project_beta_fail() { return 7; }
EOF

    cat > "${plugin_dir}/alpha.sh" <<'EOF'
printf 'alpha\n' >> "${PLUGIN_UTILS_TEST_LOAD_LOG}"
project_alpha_detect() { return 0; }
project_alpha_build() { printf 'alpha-build:%s\n' "$1"; }
project_alpha_info() {
    printf 'name=alpha\n'
    printf 'version=0.1.0\n'
}
EOF

    printf '%s\n' "${plugin_dir}"
}

test_plugin_utils_plugin_load_sources_plugins_in_sorted_order_and_tracks_types() {
    local temp_dir plugin_dir
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    plugin_dir="$(plugin_utils_test_make_plugin_dir "${temp_dir}")"
    export PLUGIN_UTILS_TEST_LOAD_LOG="${temp_dir}/load.log"
    : > "${PLUGIN_UTILS_TEST_LOAD_LOG}"

    plugin_load project "${plugin_dir}"

    local -n loaded_types_ref="PLUGIN_TYPES_project"
    assert_equals "2" "${#loaded_types_ref[@]}"
    assert_equals "alpha" "${loaded_types_ref[0]}"
    assert_equals "beta" "${loaded_types_ref[1]}"
    assert_equals $'alpha\nbeta' "$(cat "${PLUGIN_UTILS_TEST_LOAD_LOG}")"
}

test_plugin_utils_plugin_load_rejects_missing_directory() {
    local temp_dir output status
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    output="$({ plugin_load project "${temp_dir}/missing"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "Plugin directory not found" "${output}"
}

test_plugin_utils_plugin_has_reports_defined_and_missing_actions() {
    local temp_dir plugin_dir
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    plugin_dir="$(plugin_utils_test_make_plugin_dir "${temp_dir}")"
    export PLUGIN_UTILS_TEST_LOAD_LOG="${temp_dir}/load.log"
    : > "${PLUGIN_UTILS_TEST_LOAD_LOG}"
    plugin_load project "${plugin_dir}"

    assert_status_code 0 "plugin_has project alpha build"
    assert_status_code 1 "plugin_has project alpha deploy"
}

test_plugin_utils_plugin_call_invokes_function_and_returns_output() {
    local temp_dir plugin_dir output
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    plugin_dir="$(plugin_utils_test_make_plugin_dir "${temp_dir}")"
    export PLUGIN_UTILS_TEST_LOAD_LOG="${temp_dir}/load.log"
    : > "${PLUGIN_UTILS_TEST_LOAD_LOG}"
    plugin_load project "${plugin_dir}"

    output="$(plugin_call project alpha build demo)"

    assert_equals "alpha-build:demo" "${output}"
}

test_plugin_utils_plugin_call_reports_missing_action() {
    local temp_dir plugin_dir output status
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    plugin_dir="$(plugin_utils_test_make_plugin_dir "${temp_dir}")"
    export PLUGIN_UTILS_TEST_LOAD_LOG="${temp_dir}/load.log"
    : > "${PLUGIN_UTILS_TEST_LOAD_LOG}"
    plugin_load project "${plugin_dir}"

    output="$({ plugin_call project alpha deploy; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "Plugin project/alpha does not implement 'deploy'" "${output}"
}

test_plugin_utils_plugin_call_reports_plugin_failure_exit_code() {
    local temp_dir plugin_dir output status
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    plugin_dir="$(plugin_utils_test_make_plugin_dir "${temp_dir}")"
    export PLUGIN_UTILS_TEST_LOAD_LOG="${temp_dir}/load.log"
    : > "${PLUGIN_UTILS_TEST_LOAD_LOG}"
    plugin_load project "${plugin_dir}"

    output="$({ plugin_call project beta fail; } 2>&1)"
    status=$?

    assert_equals "7" "${status}"
    assert_matches "Plugin project/beta 'fail' failed \(exit 7\)" "${output}"
}

test_plugin_utils_plugin_read_parses_key_value_output() {
    local temp_dir plugin_dir
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    plugin_dir="$(plugin_utils_test_make_plugin_dir "${temp_dir}")"
    export PLUGIN_UTILS_TEST_LOAD_LOG="${temp_dir}/load.log"
    : > "${PLUGIN_UTILS_TEST_LOAD_LOG}"
    plugin_load project "${plugin_dir}"

    declare -A info=()
    plugin_read project beta info info

    assert_equals "beta" "${info[name]}"
    assert_equals "1.2.3" "${info[version]}"
    assert_equals "contains=equals" "${info[note]}"
}

test_plugin_utils_plugin_read_reports_failure_and_leaves_no_partial_data() {
    local temp_dir plugin_dir output status
    temp_dir="$(harness_make_temp_dir "plugin-utils")"
    plugin_dir="$(plugin_utils_test_make_plugin_dir "${temp_dir}")"
    export PLUGIN_UTILS_TEST_LOAD_LOG="${temp_dir}/load.log"
    : > "${PLUGIN_UTILS_TEST_LOAD_LOG}"
    plugin_load project "${plugin_dir}"

    declare -A info=([seed]="value")
    output="$({ plugin_read project beta fail info; } 2>&1)"
    status=$?

    assert_equals "7" "${status}"
    assert_matches "Plugin project/beta 'fail' failed \(exit 7\)" "${output}"
    assert_equals "value" "${info[seed]}"
}

test_plugin_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${PLUGIN_UTILS_SCRIPT}\"; source \"${PLUGIN_UTILS_SCRIPT}\"; type plugin_load >/dev/null'"
}
