#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

VCS_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/vcs_utils.sh"
# shellcheck source=scripts/utils/vcs_utils.sh
source "${VCS_UTILS_SCRIPT}"

vcs_utils_test_git() {
    local git_home="$1"
    shift
    HOME="${git_home}" XDG_CONFIG_HOME="${git_home}/xdg" GIT_CONFIG_NOSYSTEM=1 git "$@"
}

vcs_utils_test_make_remote_fixture() {
    local temp_dir="$1"
    local name="$2"
    local -n remote_ref="$3"
    local -n work_ref="$4"
    # shellcheck disable=SC2034  # nameref is the output channel for the caller
    local -n initial_ref="$5"
    # shellcheck disable=SC2034  # nameref is the output channel for the caller
    local -n second_ref="$6"

    remote_ref="${temp_dir}/${name}.git"
    work_ref="${temp_dir}/${name}-work"
    local git_home="${temp_dir}/${name}-git-home"
    mkdir -p "${git_home}/xdg"

    vcs_utils_test_git "${git_home}" init --bare "${remote_ref}" >/dev/null 2>&1
    vcs_utils_test_git "${git_home}" init -b main "${work_ref}" >/dev/null 2>&1
    vcs_utils_test_git "${git_home}" -C "${work_ref}" config user.name "Alloy Tests"
    vcs_utils_test_git "${git_home}" -C "${work_ref}" config user.email "alloy-tests@example.com"
    vcs_utils_test_git "${git_home}" -C "${work_ref}" remote add origin "${remote_ref}"

    printf 'first\n' > "${work_ref}/payload.txt"
    vcs_utils_test_git "${git_home}" -C "${work_ref}" add payload.txt
    vcs_utils_test_git "${git_home}" -C "${work_ref}" commit -m "initial" >/dev/null 2>&1
    # shellcheck disable=SC2034  # nameref assignment is observed through the caller's referenced variable
    initial_ref="$(vcs_utils_test_git "${git_home}" -C "${work_ref}" rev-parse HEAD)"
    vcs_utils_test_git "${git_home}" -C "${work_ref}" tag v1.0.0
    vcs_utils_test_git "${git_home}" -C "${work_ref}" push -u origin main --tags >/dev/null 2>&1
    vcs_utils_test_git "${git_home}" -C "${remote_ref}" symbolic-ref HEAD refs/heads/main

    printf 'second\n' > "${work_ref}/payload.txt"
    vcs_utils_test_git "${git_home}" -C "${work_ref}" commit -am "second" >/dev/null 2>&1
    # shellcheck disable=SC2034  # nameref assignment is observed through the caller's referenced variable
    second_ref="$(vcs_utils_test_git "${git_home}" -C "${work_ref}" rev-parse HEAD)"
    vcs_utils_test_git "${git_home}" -C "${work_ref}" push origin main >/dev/null 2>&1
}

test_vcs_utils_clone_or_validate_clones_missing_target_and_checks_out_ref() {
    local temp_dir remote_repo initial_commit second_commit
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin" remote_repo VCS_UTILS_TEST_UNUSED_WORK_REPO initial_commit second_commit

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" false

    assert_equals "${second_commit}" "$(git -C "${target_dir}" rev-parse HEAD)"
    assert_equals "${remote_repo}" "$(git -C "${target_dir}" config --get remote.origin.url)"
}

test_vcs_utils_clone_or_validate_updates_existing_clean_checkout_to_requested_ref() {
    local temp_dir remote_repo initial_commit second_commit
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin" remote_repo VCS_UTILS_TEST_UNUSED_WORK_REPO initial_commit second_commit

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_repo}" "v1.0.0" "${target_dir}" false
    assert_equals "${initial_commit}" "$(git -C "${target_dir}" rev-parse HEAD)"

    vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" false
    assert_equals "${second_commit}" "$(git -C "${target_dir}" rev-parse HEAD)"
}

test_vcs_utils_clone_or_validate_reclones_when_remote_url_changes() {
    local temp_dir remote_one remote_two second_two
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin-one" remote_one VCS_UTILS_TEST_UNUSED_WORK_REPO VCS_UTILS_TEST_UNUSED_INITIAL VCS_UTILS_TEST_UNUSED_SECOND
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin-two" remote_two VCS_UTILS_TEST_UNUSED_WORK_REPO VCS_UTILS_TEST_UNUSED_INITIAL second_two

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_one}" "main" "${target_dir}" false
    printf 'stale\n' > "${target_dir}/stale.txt"

    vcs_clone_or_validate git "${remote_two}" "main" "${target_dir}" false

    assert_equals "${remote_two}" "$(git -C "${target_dir}" config --get remote.origin.url)"
    assert_equals "${second_two}" "$(git -C "${target_dir}" rev-parse HEAD)"
    assert_status_code 1 "test -e '${target_dir}/stale.txt'"
}

test_vcs_utils_clone_or_validate_rejects_dirty_checkout_when_not_allowed() {
    local temp_dir remote_repo initial_commit second_commit
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin" remote_repo VCS_UTILS_TEST_UNUSED_WORK_REPO initial_commit second_commit

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" false
    printf 'dirty\n' >> "${target_dir}/payload.txt"

    local output status
    output="$({ vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" false; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "Git checkout is dirty" "${output}"
}

test_vcs_utils_clone_or_validate_allows_dirty_checkout_at_requested_ref() {
    local temp_dir remote_repo initial_commit second_commit
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin" remote_repo VCS_UTILS_TEST_UNUSED_WORK_REPO initial_commit second_commit

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" false
    printf 'dirty\n' >> "${target_dir}/payload.txt"

    vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" true

    assert_equals "${second_commit}" "$(git -C "${target_dir}" rev-parse HEAD)"
}

test_vcs_utils_clone_or_validate_rejects_dirty_checkout_when_ref_change_would_discard_edits() {
    local temp_dir remote_repo initial_commit second_commit
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin" remote_repo VCS_UTILS_TEST_UNUSED_WORK_REPO initial_commit second_commit

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_repo}" "v1.0.0" "${target_dir}" false
    printf 'dirty\n' >> "${target_dir}/payload.txt"

    local output status
    output="$({ vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" true; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "cannot switch to ref 'main' without discarding changes" "${output}"
    assert_equals "${initial_commit}" "$(git -C "${target_dir}" rev-parse HEAD)"
}

test_vcs_utils_get_provenance_reports_expected_fields() {
    local temp_dir remote_repo initial_commit second_commit
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin" remote_repo VCS_UTILS_TEST_UNUSED_WORK_REPO initial_commit second_commit

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" false
    printf 'dirty\n' >> "${target_dir}/payload.txt"

    local output
    output="$(vcs_get_provenance "${target_dir}")"

    assert_matches "NAME=clone" "${output}"
    assert_matches "URL=${remote_repo}" "${output}"
    assert_matches "COMMIT=${second_commit}" "${output}"
    assert_matches "DESCRIBE=" "${output}"
    assert_matches "DIRTY=true" "${output}"
}

test_vcs_utils_write_alloy_repo_info_writes_expected_file() {
    local temp_dir remote_repo initial_commit second_commit
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    vcs_utils_test_make_remote_fixture "${temp_dir}" "origin" remote_repo VCS_UTILS_TEST_UNUSED_WORK_REPO initial_commit second_commit

    local target_dir="${temp_dir}/clone"
    vcs_clone_or_validate git "${remote_repo}" "main" "${target_dir}" false

    write_alloy_repo_info "${target_dir}"

    local info_file="${target_dir}/.alloy_repo_info"
    assert_status_code 0 "test -f '${info_file}'"
    assert_matches "NAME=clone" "$(cat "${info_file}")"
    assert_matches "URL=${remote_repo}" "$(cat "${info_file}")"
    assert_matches "COMMIT=${second_commit}" "$(cat "${info_file}")"
    assert_matches "DIRTY=false" "$(cat "${info_file}")"
}

test_vcs_utils_write_alloy_repo_info_is_noop_for_non_repository_paths() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "vcs-utils")"
    mkdir -p "${temp_dir}/plain"

    write_alloy_repo_info "${temp_dir}/plain"

    assert_status_code 1 "test -e '${temp_dir}/plain/.alloy_repo_info'"
}

test_vcs_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${VCS_UTILS_SCRIPT}\"; source \"${VCS_UTILS_SCRIPT}\"; type vcs_clone_or_validate >/dev/null'"
}
