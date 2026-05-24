#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

PROJECT_PLUGIN_API="$(harness_repo_root)/scripts/plugins/project.sh"

project_plugins_test_make_sdk_with_plugins() {
    local temp_dir="$1"
    local sdk_dir="${temp_dir}/sdk"
    mkdir -p "${sdk_dir}/scripts/plugins/project" "${sdk_dir}/host/bin" "${sdk_dir}/staging/usr/lib/erlang/lib"

    cp "$(harness_repo_root)/scripts/plugins/project/erlang.sh" "${sdk_dir}/scripts/plugins/project/erlang.sh"
    cp "$(harness_repo_root)/scripts/plugins/project/elixir.sh" "${sdk_dir}/scripts/plugins/project/elixir.sh"

    printf '%s\n' "${sdk_dir}"
}

project_plugins_test_write_fake_rebar3() {
    local sdk_dir="$1"
    local logfile="$2"
    cat > "${sdk_dir}/host/bin/rebar3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PROJECT_PLUGIN_TEST_REBAR3_LOG}"
if [[ "${1:-}" == "as" ]] && [[ "${3:-}" == "release" ]]; then
    mkdir -p "${PROJECT_PLUGIN_TEST_PROJECT_DIR}/_build/${2}/rel/demo_release/lib"
fi
EOF
    chmod +x "${sdk_dir}/host/bin/rebar3"
}

project_plugins_test_write_fake_mix() {
    local sdk_dir="$1"
cat > "${sdk_dir}/host/bin/mix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PROJECT_PLUGIN_TEST_MIX_LOG}"
if [[ "${1:-}" == "release" ]]; then
    rel_dir="${PROJECT_PLUGIN_TEST_PROJECT_DIR}/_build/prod/rel/demo_release"
    mkdir -p "${rel_dir}/releases/1.0.0" "${rel_dir}/lib/crypto-0.1/ebin"
    printf 'placeholder\n' > "${rel_dir}/lib/crypto-0.1/ebin/crypto.beam"
fi
EOF
    chmod +x "${sdk_dir}/host/bin/mix"
}

project_plugins_test_make_target_erlang_tree() {
    local sdk_dir="$1"
    mkdir -p \
        "${sdk_dir}/staging/usr/lib/erlang/erts-13.2/bin" \
        "${sdk_dir}/staging/usr/lib/erlang/lib/crypto-1.0/ebin" \
        "${sdk_dir}/staging/usr/lib/erlang/lib/crypto-1.0/priv" \
        "${sdk_dir}/staging/usr/lib/erlang/lib/erl_interface-5.4/include" \
        "${sdk_dir}/staging/usr/lib/erlang/lib/erl_interface-5.4/lib"
    printf 'target-crypto\n' > "${sdk_dir}/staging/usr/lib/erlang/lib/crypto-1.0/ebin/crypto.beam"
}

test_project_plugins_erlang_build_accepts_combined_profiles_and_runs_single_release_build() {
    local temp_dir sdk_dir project_dir
    temp_dir="$(harness_make_temp_dir "project-plugins")"
    sdk_dir="$(project_plugins_test_make_sdk_with_plugins "${temp_dir}")"
    project_plugins_test_make_target_erlang_tree "${sdk_dir}"

    local rebar_log="${temp_dir}/rebar.log"
    : > "${rebar_log}"
    project_plugins_test_write_fake_rebar3 "${sdk_dir}" "${rebar_log}"

    project_dir="${temp_dir}/erlang-project"
    mkdir -p "${project_dir}"
    : > "${project_dir}/rebar.config"

    export PROJECT_PLUGIN_TEST_REBAR3_LOG="${rebar_log}"
    export PROJECT_PLUGIN_TEST_PROJECT_DIR="${project_dir}"
    export ALLOY_SDK_DIR="${sdk_dir}"
    export TARGET_ERLANG="${sdk_dir}/staging/usr/lib/erlang"
    export HOST_REBAR3="${sdk_dir}/host/bin/rebar3"

    # shellcheck source=scripts/plugins/project.sh
    source "${PROJECT_PLUGIN_API}"
    project_load_plugins "${sdk_dir}"

    local detected_type release_dir
    project_detect_type "${project_dir}" detected_type
    assert_equals "erlang" "${detected_type}"
    assert_status_code 0 "project_has_capability erlang supports_multi_profiles"

    release_dir=""
    project_build_type erlang release_dir "${project_dir}" "prod,debug"
    assert_status_code 0 "[[ -d '${release_dir}' ]]"
    assert_status_code 0 "grep -Fq 'as prod,debug get-deps' '${rebar_log}'"
    assert_status_code 0 "grep -Fq 'as prod,debug release --system_libs ${sdk_dir}/staging/usr/lib/erlang --include-erts ${sdk_dir}/staging/usr/lib/erlang' '${rebar_log}'"
}

test_project_plugins_elixir_build_uses_target_runtime_and_rejects_multi_profile_capability() {
    local temp_dir sdk_dir project_dir
    temp_dir="$(harness_make_temp_dir "project-plugins")"
    sdk_dir="$(project_plugins_test_make_sdk_with_plugins "${temp_dir}")"
    project_plugins_test_make_target_erlang_tree "${sdk_dir}"
    project_plugins_test_write_fake_mix "${sdk_dir}"

    local mix_log="${temp_dir}/mix.log"
    : > "${mix_log}"
    project_dir="${temp_dir}/elixir-project"
    mkdir -p "${project_dir}"
    : > "${project_dir}/mix.exs"

    export PROJECT_PLUGIN_TEST_MIX_LOG="${mix_log}"
    export PROJECT_PLUGIN_TEST_PROJECT_DIR="${project_dir}"
    export ALLOY_SDK_DIR="${sdk_dir}"
    export TARGET_ERLANG="${sdk_dir}/staging/usr/lib/erlang"
    export HOST_MIX="${sdk_dir}/host/bin/mix"

    # shellcheck source=scripts/plugins/project.sh
    source "${PROJECT_PLUGIN_API}"
    project_load_plugins "${sdk_dir}"

    local detected_type release_dir
    project_detect_type "${project_dir}" detected_type
    assert_equals "elixir" "${detected_type}"
    assert_status_code 1 "project_has_capability elixir supports_multi_profiles"

    release_dir=""
    project_build_type elixir release_dir "${project_dir}" "default"
    assert_status_code 0 "[[ -d '${release_dir}/erts-13.2' ]]"
    assert_status_code 0 "grep -Fq 'deps.get --only prod' '${mix_log}'"
    assert_status_code 0 "grep -Fq 'compile' '${mix_log}'"
    assert_status_code 0 "grep -Fq 'release --overwrite' '${mix_log}'"
    assert_status_code 0 "grep -Fq 'target-crypto' '${release_dir}/lib/crypto-1.0/ebin/crypto.beam'"
}
