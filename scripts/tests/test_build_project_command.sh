#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

BUILD_PROJECT_COMMAND="$(harness_repo_root)/scripts/commands/build-project.sh"

build_project_test_write_fake_sdk() {
    local sdk_root="$1"
    local marker="$2"

    mkdir -p "${sdk_root}/scripts"
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
    : > "${sdk_root}/ALLOY_SDK_MANIFEST"
    : > "${sdk_root}/.alloy_relocation_manifest"
    printf '%s\n' '@@ALLOY_SDK_DIR@@' > "${sdk_root}/.alloy_sdk_dir"
}

build_project_test_make_command_fixture() {
    local temp_dir="$1"
    local root_dir="${temp_dir}/fixture"

    mkdir -p "${root_dir}/scripts/commands" "${root_dir}/scripts/utils"
    cp "${BUILD_PROJECT_COMMAND}" "${root_dir}/scripts/commands/build-project.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${root_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${root_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${root_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/file_utils.sh" "${root_dir}/scripts/utils/file_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/sdk_utils.sh" "${root_dir}/scripts/utils/sdk_utils.sh"
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

test_build_project_command_sdk_mode_uses_current_sdk() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    build_project_test_write_fake_sdk "${root_dir}" "self"

    local output status
    output="$(ALLOY_ROOT="${root_dir}" "${root_dir}/scripts/commands/build-project.sh" demo-src 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "alloy build project execution is not implemented yet \\(Task 6.2\\+\\)" "${output}"
}

test_build_project_command_repo_mode_auto_selects_single_archive() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk" "${root_dir}/_cache"
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"
    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "archive"

    local output
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${root_dir}/_cache/sdk-install" \
        "${root_dir}/scripts/commands/build-project.sh" project-src 2>&1)"

    assert_matches "MARKER=archive" "${output}"
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
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "first"
    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${root_dir}/_cache/sdk-install" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "second"
    local output
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${root_dir}/_cache/sdk-install" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" 2>&1)"

    assert_matches "MARKER=second" "${output}"
}

test_build_project_command_reuses_archive_install_when_hash_unchanged() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "build-project-cmd")"
    local root_dir
    root_dir="$(build_project_test_make_command_fixture "${temp_dir}")"

    mkdir -p "${root_dir}/artefacts/sdk" "${root_dir}/_cache"
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "stable"
    local install_root="${root_dir}/_cache/sdk-install"
    local install_dir="${install_root}/sdk-demo-1.0.0-x86_64"

    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null

    local before_mtime
    before_mtime="$(stat -c '%Y' "${install_dir}/.alloy_sdk_install")"

    sleep 1
    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null

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
    local archive_path="${root_dir}/artefacts/sdk/sdk-demo-1.0.0-x86_64.tar.gz"
    local install_root="${root_dir}/_cache/sdk-install"
    local install_dir="${install_root}/sdk-demo-1.0.0-x86_64"

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "first"
    ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src --sdk "${archive_path}" >/dev/null

    build_project_test_make_sdk_archive "${temp_dir}" "${archive_path}" "second"
    local output
    output="$(ALLOY_ROOT="${root_dir}" ALLOY_SDK_INSTALL_ROOT="${install_root}" \
        "${root_dir}/scripts/commands/build-project.sh" project-src 2>&1)"

    assert_matches "MARKER=second" "${output}"
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
