#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

BUILD_SDK_COMMAND="$(harness_repo_root)/scripts/commands/build-sdk.sh"

build_sdk_test_make_fixture() {
    local temp_dir="$1"
    local root_dir="${temp_dir}/fixture"
    mkdir -p "${root_dir}/scripts/commands" "${root_dir}/scripts/utils" "${root_dir}/scripts/tests/lib"
    cp "${BUILD_SDK_COMMAND}" "${root_dir}/scripts/commands/build-sdk.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${root_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${root_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${root_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/vcs_utils.sh" "${root_dir}/scripts/utils/vcs_utils.sh"
    cp "$(harness_repo_root)/scripts/argparse.sh" "${root_dir}/scripts/argparse.sh"
    chmod +x "${root_dir}/scripts/commands/build-sdk.sh"
    printf '%s\n' "${root_dir}"
}

build_sdk_test_git() {
    local git_home="$1"
    shift
    HOME="${git_home}" XDG_CONFIG_HOME="${git_home}/xdg" GIT_CONFIG_NOSYSTEM=1 git "$@"
}

build_sdk_test_write_registry() {
    local repo_dir="$1"
    local nugget_id="$2"

    mkdir -p "${repo_dir}/${nugget_id}"
    cat > "${repo_dir}/.nuggets" <<EOF
{nugget_registry, <<"1.0">>, [{nuggets, [<<"${nugget_id}/.nugget">>]}]}.
EOF
    cat > "${repo_dir}/${nugget_id}/.nugget" <<EOF
{nugget, <<"1.0">>, [{id, ${nugget_id}}, {category, feature}]}.
EOF
}

build_sdk_test_make_remote_nugget_repo() {
    local temp_dir="$1"
    local name="$2"
    local -n remote_ref="$3"

    local git_home="${temp_dir}/${name}-git-home"
    local work_dir="${temp_dir}/${name}-work"
    remote_ref="${temp_dir}/${name}.git"
    mkdir -p "${git_home}/xdg"

    build_sdk_test_git "${git_home}" init --bare "${remote_ref}" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" init -b main "${work_dir}" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${work_dir}" config user.name "Alloy Tests"
    build_sdk_test_git "${git_home}" -C "${work_dir}" config user.email "alloy-tests@example.com"
    build_sdk_test_git "${git_home}" -C "${work_dir}" remote add origin "${remote_ref}"
    build_sdk_test_write_registry "${work_dir}" "${name}_feature"
    printf '%s\n' "${name}" > "${work_dir}/remote-marker.txt"
    build_sdk_test_git "${git_home}" -C "${work_dir}" add .
    build_sdk_test_git "${git_home}" -C "${work_dir}" commit -m "initial" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${work_dir}" push -u origin main >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${remote_ref}" symbolic-ref HEAD refs/heads/main
}

test_build_sdk_command_help_shows_canonical_usage() {
    local output status

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR \
        "${BUILD_SDK_COMMAND}" --help 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Usage: alloy build sdk PRODUCT_NUGGET \\[OPTIONS\\]" "${output}"
    assert_matches "--clean-package PKG" "${output}"
    assert_status_code 1 "printf '%s\n' '${output}' | grep -F -- '-c PKG'"
}

test_build_sdk_command_requires_product_nugget() {
    local output status

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR \
        "${BUILD_SDK_COMMAND}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Missing PRODUCT_NUGGET" "${output}"
}

test_build_sdk_command_rejects_sdk_mode() {
    local output status

    output="$(ALLOY_MODE=sdk "${BUILD_SDK_COMMAND}" demo 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "build sdk is only available in repository mode" "${output}"
}

test_build_sdk_command_direct_invocation_infers_sdk_mode_from_manifest_and_rejects_it() {
    local temp_dir root_dir command_path output status
    temp_dir="$(harness_make_temp_dir "build-sdk-sdk-mode")"
    root_dir="$(build_sdk_test_make_fixture "${temp_dir}")"
    command_path="${root_dir}/scripts/commands/build-sdk.sh"
    : > "${root_dir}/ALLOY_SDK_MANIFEST"

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR -u ALLOY_ARTEFACT_DIR -u ALLOY_CACHE_DIR \
        "${command_path}" demo 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "build sdk is only available in repository mode" "${output}"
}

test_build_sdk_command_creates_expected_layout_and_reports_sources() {
    local temp_dir build_root env_source cli_source output status
    temp_dir="$(harness_make_temp_dir "build-sdk-layout")"
    build_root="${temp_dir}/build"
    env_source="${temp_dir}/env_one"
    cli_source="${temp_dir}/local_one"
    build_sdk_test_write_registry "${env_source}" env_one_feature
    build_sdk_test_write_registry "${cli_source}" local_one_feature

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_NUGGET_PATH="${env_source}" \
        "${BUILD_SDK_COMMAND}" demo_product \
        -n "${cli_source}" \
        --include-sources \
        --allow-dirty 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/plan' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/targets' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/staging' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/motherlode' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/builtin/.nuggets' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/env_one/.nuggets' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/local_one/.nuggets' ]]"
    assert_matches "Initialized SDK build workspace for demo_product" "${output}"
    assert_matches "Additional command-line nugget sources: 1" "${output}"
    assert_matches "Additional environment nugget sources: 1" "${output}"
    assert_matches "Staged nugget repositories: 3" "${output}"
    assert_matches "Dirty VCS checkouts are allowed" "${output}"
    assert_matches "Legal-info source export was requested" "${output}"
}

test_build_sdk_command_stages_mixed_sources_with_conflict_safe_names() {
    local temp_dir build_root env_source cli_source remote_repo output status
    temp_dir="$(harness_make_temp_dir "build-sdk-stage")"
    build_root="${temp_dir}/build"
    env_source="${temp_dir}/env/shared"
    cli_source="${temp_dir}/cli/shared"
    build_sdk_test_write_registry "${env_source}" env_feature
    build_sdk_test_write_registry "${cli_source}" cli_feature
    printf 'env\n' > "${env_source}/source-marker.txt"
    printf 'cli\n' > "${cli_source}/source-marker.txt"
    build_sdk_test_make_remote_nugget_repo "${temp_dir}" remote_nuggets remote_repo

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_NUGGET_PATH="${env_source}" \
        "${BUILD_SDK_COMMAND}" demo_product \
        -n "${cli_source}" \
        -n "git+file://${remote_repo}#main" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/builtin/.nuggets' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/shared/source-marker.txt' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/shared_2/source-marker.txt' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/remote_nuggets/remote-marker.txt' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/motherlode/remote_nuggets/.git' ]]"
    assert_matches "Staged nugget repositories: 4" "${output}"
}

test_build_sdk_command_rejects_missing_local_nugget_source() {
    local temp_dir build_root output status
    temp_dir="$(harness_make_temp_dir "build-sdk-missing-source")"
    build_root="${temp_dir}/build"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "${temp_dir}/missing" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Local nugget source does not exist" "${output}"
}

test_build_sdk_command_rejects_dirty_local_vcs_source_by_default() {
    local temp_dir build_root local_source git_home output status
    temp_dir="$(harness_make_temp_dir "build-sdk-dirty-local")"
    build_root="${temp_dir}/build"
    local_source="${temp_dir}/local_repo"
    git_home="${temp_dir}/git-home"
    mkdir -p "${git_home}/xdg"

    build_sdk_test_git "${git_home}" init -b main "${local_source}" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${local_source}" config user.name "Alloy Tests"
    build_sdk_test_git "${git_home}" -C "${local_source}" config user.email "alloy-tests@example.com"
    build_sdk_test_write_registry "${local_source}" local_feature
    build_sdk_test_git "${git_home}" -C "${local_source}" add .
    build_sdk_test_git "${git_home}" -C "${local_source}" commit -m "initial" >/dev/null 2>&1
    printf 'dirty\n' >> "${local_source}/local_feature/.nugget"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "${local_source}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Local nugget source is dirty" "${output}"
}

test_build_sdk_command_allows_dirty_existing_vcs_stage_only_when_requested() {
    local temp_dir build_root remote_repo staged_repo output status
    temp_dir="$(harness_make_temp_dir "build-sdk-dirty-vcs")"
    build_root="${temp_dir}/build"
    build_sdk_test_make_remote_nugget_repo "${temp_dir}" remote_nuggets remote_repo

    ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "git+file://${remote_repo}#main" >/dev/null
    staged_repo="${build_root}/sdk/demo_product/motherlode/remote_nuggets"
    printf 'dirty\n' >> "${staged_repo}/remote-marker.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "git+file://${remote_repo}#main" 2>&1)"
    status=$?
    assert_equals "2" "${status}"
    assert_matches "Git checkout is dirty" "${output}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product --allow-dirty \
        -n "git+file://${remote_repo}#main" 2>&1)"
    status=$?
    assert_equals "0" "${status}"
    assert_matches "Dirty VCS checkouts are allowed" "${output}"
}

test_build_sdk_command_clean_removes_existing_workspace() {
    local temp_dir build_root workspace output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean")"
    build_root="${temp_dir}/build"
    workspace="${build_root}/sdk/demo_product"
    mkdir -p "${workspace}"
    printf 'stale\n' > "${workspace}/stale.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -c 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 1 "[[ -e '${workspace}/stale.txt' ]]"
    assert_status_code 0 "[[ -d '${workspace}/plan' ]]"
    assert_matches "Initialized SDK build workspace for demo_product" "${output}"
}

test_build_sdk_command_short_c_with_value_is_rejected_as_extra_positional() {
    local temp_dir build_root workspace output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean-package")"
    build_root="${temp_dir}/build"
    workspace="${build_root}/sdk/demo_product"
    mkdir -p "${workspace}"
    printf 'keep\n' > "${workspace}/stale.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -c busybox 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_status_code 0 "[[ -e '${workspace}/stale.txt' ]]"
    assert_matches "Unexpected positional arguments: busybox" "${output}"
}

test_build_sdk_command_long_clean_package_is_supported() {
    local temp_dir build_root output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean-package-long")"
    build_root="${temp_dir}/build"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product --clean-package busybox 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Queued clean-package requests: busybox" "${output}"
}

test_build_sdk_command_rejects_invalid_allow_dirty_env_value() {
    local output status

    output="$(ALLOY_ALLOW_DIRTY=maybe \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "ALLOY_ALLOW_DIRTY must be true or false" "${output}"
}
