#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

BUILD_PROJECT_COMMAND="$(harness_repo_root)/scripts/commands/build-project.sh"

build_project_test_write_fake_sdk() {
    local sdk_root="$1"
    local marker="$2"
    local triplet="${3:-arm-buildroot-linux-gnueabihf}"

    mkdir -p \
        "${sdk_root}/scripts" \
        "${sdk_root}/host/bin" \
        "${sdk_root}/host/usr/bin" \
        "${sdk_root}/host/usr/lib/erlang" \
        "${sdk_root}/host/${triplet}/sysroot/usr/include" \
        "${sdk_root}/host/${triplet}/sysroot/usr/lib/pkgconfig" \
        "${sdk_root}/staging/usr/lib/erlang/erts-13.2/include" \
        "${sdk_root}/staging/usr/lib/erlang/erts-13.2/lib" \
        "${sdk_root}/staging/usr/lib/erlang/lib/erl_interface-5.4/include" \
        "${sdk_root}/staging/usr/lib/erlang/lib/erl_interface-5.4/lib" \
        "${sdk_root}/images"

    local tool_name
    for tool_name in gcc g++ ld ar as nm strip objcopy objdump ranlib readelf; do
        cat > "${sdk_root}/host/bin/${triplet}-${tool_name}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${sdk_root}/host/bin/${triplet}-${tool_name}"
    done

    cat > "${sdk_root}/host/bin/pkg-config" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${sdk_root}/host/bin/pkg-config"
    cat > "${sdk_root}/host/bin/rebar3" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${sdk_root}/host/bin/rebar3"
    cat > "${sdk_root}/host/usr/bin/mix" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${sdk_root}/host/usr/bin/mix"

    cat > "${sdk_root}/alloy" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "MARKER=${marker}"
printf 'ARGS:'
for arg in "\$@"; do
    printf ' <%s>' "\$arg"
done
printf '\n'
FAKE
    chmod +x "${sdk_root}/alloy"
    cat > "${sdk_root}/ALLOY_SDK_MANIFEST" <<EOF
{sdk_manifest, <<"1.0">>, [
    {product, <<"${marker}">>},
    {build_timestamp, <<"2026-05-24T00:00:00Z">>}
]}.
EOF
    : > "${sdk_root}/.alloy_relocation_manifest"
    printf '%s\n' '@@ALLOY_SDK_DIR@@' > "${sdk_root}/.alloy_sdk_dir"
    cat > "${sdk_root}/scripts/alloy_context.sh" <<EOF
#!/usr/bin/env bash
export ALLOY_CONFIG_HOST_REBAR3="${ALLOY_SDK_DIR}/host/bin/rebar3"
export ALLOY_CONFIG_HOST_MIX="${ALLOY_SDK_DIR}/host/bin/mix"
export ALLOY_CONFIG_TARGET_ERLANG_ROOT="${ALLOY_SDK_DIR}/staging/usr/lib/erlang"
export ALLOY_CONFIG_TARGET_ARCH_TRIPLET="${triplet}"
EOF
}

build_project_test_write_mock_project_plugin() {
    local sdk_root="$1"

    mkdir -p "${sdk_root}/scripts/plugins/project"
    cat > "${sdk_root}/scripts/plugins/project/mock.sh" <<'EOF'
project_mock_detect() {
    local project_dir="$1"
    [[ -f "${project_dir}/project.mock" ]]
}

project_mock_build() {
    local -n resref="$1"
    local project_dir="$2"
    local profile="$3"
    local target_erlang="${TARGET_ERLANG:-${ALLOY_SDK_DIR}/staging/usr/lib/erlang}"

    local output_release_path="${project_dir}/_build/${profile}/rel/mock_release"
    mkdir -p "${output_release_path}/lib"
    printf 'profile=%s\ntarget_erlang=%s\ncc=%s\n' \
        "${profile}" "${target_erlang}" "${CC:-}" > "${output_release_path}/build-info.txt"
    resref="${output_release_path}"
}

project_mock_capabilities() {
    printf 'supports_multi_profiles=true\n'
}
EOF

    cat > "${sdk_root}/scripts/plugins/project/nomulti.sh" <<'EOF'

project_nomulti_detect() {
    local project_dir="$1"
    [[ -f "${project_dir}/project.nomulti" ]]
}

project_nomulti_build() {
    local -n resref="$1"
    local project_dir="$2"
    local profile="$3"
    local target_erlang="${TARGET_ERLANG:-${ALLOY_SDK_DIR}/staging/usr/lib/erlang}"

    local output_release_path="${project_dir}/_build/${profile}/rel/nomulti_release"
    mkdir -p "${output_release_path}/lib"
    printf 'profile=%s\ntarget_erlang=%s\n' "${profile}" "${target_erlang}" > "${output_release_path}/build-info.txt"
    resref="${output_release_path}"
}

project_nomulti_capabilities() {
    printf 'supports_multi_profiles=false\n'
}
EOF
}

build_project_test_make_command_fixture() {
    local temp_dir="$1"
    local root_dir="${temp_dir}/fixture"

    mkdir -p "${root_dir}/scripts/commands" "${root_dir}/scripts/utils" "${root_dir}/scripts/plugins"
    cp "${BUILD_PROJECT_COMMAND}" "${root_dir}/scripts/commands/build-project.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${root_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${root_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${root_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/file_utils.sh" "${root_dir}/scripts/utils/file_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/manifest_utils.sh" "${root_dir}/scripts/utils/manifest_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/sdk_utils.sh" "${root_dir}/scripts/utils/sdk_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/env_utils.sh" "${root_dir}/scripts/utils/env_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/plugin_utils.sh" "${root_dir}/scripts/utils/plugin_utils.sh"
    cp "$(harness_repo_root)/scripts/plugins/project.sh" "${root_dir}/scripts/plugins/project.sh"
    cp "$(harness_repo_root)/scripts/argparse.sh" "${root_dir}/scripts/argparse.sh"

    printf '%s\n' "${root_dir}"
}

build_project_test_make_sdk_archive() {
    local temp_dir="$1"
    local archive_path="$2"
    local marker="$3"

    local source_root="${temp_dir}/sdk-src-${marker}"
    local bundle_root="sdk-${marker}"
    mkdir -p "${source_root}/${bundle_root}"
    build_project_test_write_fake_sdk "${source_root}/${bundle_root}" "${marker}"
    tar -czf "${archive_path}" -C "${source_root}" "${bundle_root}"
}

test_build_project_command_help_shows_canonical_usage() {
    local output
    output="$("${BUILD_PROJECT_COMMAND}" --help 2>&1)"

    assert_matches "Usage: alloy build project PROJECT_SOURCE" "${output}"
    assert_matches "--sdk SDK_REF" "${output}"
}

test_build_project_command_sdk_mode_detects_plugin_and_dispatches_build() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    build_project_test_write_fake_sdk "${root_dir}" "self"
    build_project_test_write_mock_project_plugin "${root_dir}"
    mkdir -p "${root_dir}/demo-project"
    : > "${root_dir}/demo-project/project.mock"

    local output
    output="$(
        ALLOY_ROOT="${root_dir}" \
            "${root_dir}/scripts/commands/build-project.sh" "${root_dir}/demo-project" --profile prod 2>&1
    )"

    assert_matches "Using SDK: self \\(built 2026-05-24T00:00:00Z\\)" "${output}"
    assert_matches "Built mock release \\(prod\\)" "${output}"
    assert_status_code 0 "test -f '${root_dir}/demo-project/_build/prod/rel/mock_release/build-info.txt'"
    assert_status_code 0 "grep -Fq 'profile=prod' '${root_dir}/demo-project/_build/prod/rel/mock_release/build-info.txt'"
    assert_status_code 0 "grep -Fq 'cc=${root_dir}/host/bin/arm-buildroot-linux-gnueabihf-gcc' '${root_dir}/demo-project/_build/prod/rel/mock_release/build-info.txt'"
}

test_build_project_command_sdk_mode_builds_once_with_combined_profiles() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    build_project_test_write_fake_sdk "${root_dir}" "self"
    build_project_test_write_mock_project_plugin "${root_dir}"
    mkdir -p "${root_dir}/demo-project"
    : > "${root_dir}/demo-project/project.mock"

    local output
    output="$(
        ALLOY_ROOT="${root_dir}" \
            "${root_dir}/scripts/commands/build-project.sh" "${root_dir}/demo-project" \
            --profile prod --profile debug 2>&1
    )"

    assert_matches "Using SDK: self \\(built 2026-05-24T00:00:00Z\\)" "${output}"
    assert_matches "Built mock release \\(prod,debug\\)" "${output}"
    assert_status_code 0 "test -f '${root_dir}/demo-project/_build/prod,debug/rel/mock_release/build-info.txt'"
    assert_status_code 0 "grep -Fq 'profile=prod,debug' '${root_dir}/demo-project/_build/prod,debug/rel/mock_release/build-info.txt'"
}

test_build_project_command_sdk_mode_fails_when_project_type_is_unknown() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    build_project_test_write_fake_sdk "${root_dir}" "self"
    build_project_test_write_mock_project_plugin "${root_dir}"
    mkdir -p "${root_dir}/unknown-project"

    local output status
    output="$(
        ALLOY_ROOT="${root_dir}" \
            "${root_dir}/scripts/commands/build-project.sh" "${root_dir}/unknown-project" 2>&1
    )"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Using SDK: self \\(built 2026-05-24T00:00:00Z\\)" "${output}"
    assert_matches "Unable to detect project type" "${output}"
}

test_build_project_command_sdk_mode_rejects_multiple_profiles_when_plugin_disallows_it() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    build_project_test_write_fake_sdk "${root_dir}" "self"
    build_project_test_write_mock_project_plugin "${root_dir}"
    mkdir -p "${root_dir}/nomulti-project"
    : > "${root_dir}/nomulti-project/project.nomulti"

    local output status
    output="$(
        ALLOY_ROOT="${root_dir}" \
            "${root_dir}/scripts/commands/build-project.sh" "${root_dir}/nomulti-project" \
            --profile prod --profile debug 2>&1
    )"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Using SDK: self \\(built 2026-05-24T00:00:00Z\\)" "${output}"
    assert_matches "does not support multiple profiles" "${output}"
}

test_build_project_command_repo_mode_auto_selects_single_archive() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk" "${root_dir}/_cache"
    mkdir -p "${root_dir}/project-src"
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"
    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "archive"

    local output
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${root_dir}/_cache/sdk-install" \
        "${root_dir}/scripts/commands/build-project.sh" project-src 2>&1)"

    assert_matches "Using SDK: archive \\(built 2026-05-24T00:00:00Z\\)" "${output}"
    local install_dir="${root_dir}/_cache/sdk-install/sdk-demo-1.0.0-x86_64"
    assert_status_code 0 "test -f '${install_dir}/ALLOY_SDK_MANIFEST'"
    assert_status_code 0 "test -f '${install_dir}/.alloy_sdk_install'"
}

test_build_project_command_repo_mode_requires_sdk_when_ambiguous() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk"
    build_project_test_make_sdk_archive "${temp_dir}" "${root_dir}/artefacts/sdk/sdk-a-1.0.0-x86_64.tar.gz" "a"
    build_project_test_make_sdk_archive "${temp_dir}" "${root_dir}/artefacts/sdk/sdk-b-1.0.0-x86_64.tar.gz" "b"

    local output status
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${root_dir}/_cache/sdk-install" \
        "${root_dir}/scripts/commands/build-project.sh" project-src 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Unable to select SDK automatically; use --sdk SDK_REF" "${output}"
    assert_matches "SDK archives in artefacts/sdk:" "${output}"
}

test_build_project_command_reinstalls_archive_when_hash_changes() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk" "${root_dir}/_cache"
    mkdir -p "${root_dir}/project-src"
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "first"
    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${root_dir}/_cache/sdk-install" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null 2>&1

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "second"
    local output
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${root_dir}/_cache/sdk-install" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" 2>&1)"

    assert_matches "Using SDK: second \\(built 2026-05-24T00:00:00Z\\)" "${output}"
}

test_build_project_command_reuses_archive_install_when_hash_unchanged() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk" "${root_dir}/_cache"
    mkdir -p "${root_dir}/project-src"
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "stable"
    local install_root="${root_dir}/_cache/sdk-install"
    local install_dir="${install_root}/sdk-demo-1.0.0-x86_64"

    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null 2>&1

    local before_mtime
    before_mtime="$(stat -c '%Y' "${install_dir}/.alloy_sdk_install")"

    sleep 1
    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null 2>&1

    local after_mtime
    after_mtime="$(stat -c '%Y' "${install_dir}/.alloy_sdk_install")"

    assert_equals "${before_mtime}" "${after_mtime}"
}

test_build_project_command_auto_selected_installed_sdk_reinstalls_when_archive_hash_changes() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk" "${root_dir}/_cache"
    mkdir -p "${root_dir}/project-src"
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"
    local install_root="${root_dir}/_cache/sdk-install"
    local install_dir="${install_root}/sdk-demo-1.0.0-x86_64"

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "first"
    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null 2>&1

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "second"
    local output
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src 2>&1)"

    assert_matches "Using SDK: second \\(built 2026-05-24T00:00:00Z\\)" "${output}"
    assert_status_code 0 "test -f '${install_dir}/.alloy_sdk_install'"
}

test_build_project_command_explicit_install_root_must_be_usable() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk"
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"
    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "archive"

    local output status
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="/proc/forbidden-sdk-root" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "ALLOY_SDK_INSTALL_ROOT is set but not usable" "${output}"
}
