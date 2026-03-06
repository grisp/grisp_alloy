#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

FILE_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/file_utils.sh"
# shellcheck source=scripts/utils/file_utils.sh
source "${FILE_UTILS_SCRIPT}"

test_file_utils_normalize_path_handles_relative_absolute_and_trailing_slashes() {
    assert_equals "/a/c" "$(normalize_path "/a/b/../c/")"
    assert_equals "a/c" "$(normalize_path "a/./b/../c//")"
    assert_equals "." "$(normalize_path "./")"
    assert_equals ".." "$(normalize_path "../")"
}

test_file_utils_normalize_path_rejects_empty_input() {
    local output status
    output="$({ normalize_path ""; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "normalize_path requires a path argument" "${output}"
}

test_file_utils_relative_path_computes_expected_paths() {
    assert_equals "../d/e" "$(relative_path "/a/b/c" "/a/b/d/e")"
    assert_equals "d/e" "$(relative_path "/a/b" "/a/b/d/e")"
    assert_equals "." "$(relative_path "/a/b/c" "/a/b/c")"
    assert_equals "../../c/d" "$(relative_path "a/b/x/y" "a/b/c/d")"
}

test_file_utils_relative_path_rejects_mixed_path_types() {
    local output status
    output="$({ relative_path "/a/b" "a/b"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "both absolute or both relative" "${output}"
}

test_file_utils_copy_with_exclusions_copies_tree_and_skips_patterns() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "file-utils")"
    local src_dir="${temp_dir}/src"
    local dst_dir="${temp_dir}/dst"
    mkdir -p "${src_dir}/nested"
    printf 'keep\n' > "${src_dir}/keep.txt"
    printf 'skip\n' > "${src_dir}/skip.log"
    printf 'keep2\n' > "${src_dir}/nested/keep2.txt"
    printf 'tmp\n' > "${src_dir}/nested/temp.tmp"

    copy_with_exclusions "${src_dir}" "${dst_dir}" "*.log" "nested/*.tmp"

    assert_status_code 0 "test -f '${dst_dir}/keep.txt'"
    assert_status_code 1 "test -f '${dst_dir}/skip.log'"
    assert_status_code 0 "test -f '${dst_dir}/nested/keep2.txt'"
    assert_status_code 1 "test -f '${dst_dir}/nested/temp.tmp'"
}

test_file_utils_copy_with_exclusions_rejects_missing_source() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "file-utils")"
    local output status
    output="$({ copy_with_exclusions "${temp_dir}/missing" "${temp_dir}/dst"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Source path does not exist" "${output}"
}

test_file_utils_copy_with_exclusions_requires_rsync() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "file-utils")"
    local src_dir="${temp_dir}/src"
    local dst_dir="${temp_dir}/dst"
    mkdir -p "${src_dir}"
    printf 'payload\n' > "${src_dir}/file.txt"

    local output status
    output="$(PATH="" copy_with_exclusions "${src_dir}" "${dst_dir}" 2>&1)"
    status=$?

    assert_equals "127" "${status}"
    assert_matches "Required command not found: rsync" "${output}"
}

test_file_utils_merge_directories_overrides_existing_files() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "file-utils")"
    local src_dir="${temp_dir}/src"
    local dst_dir="${temp_dir}/dst"
    mkdir -p "${src_dir}" "${dst_dir}"
    printf 'new\n' > "${src_dir}/shared.txt"
    printf 'added\n' > "${src_dir}/added.txt"
    printf 'old\n' > "${dst_dir}/shared.txt"
    printf 'keep\n' > "${dst_dir}/keep.txt"

    merge_directories "${src_dir}" "${dst_dir}"

    assert_equals "new" "$(cat "${dst_dir}/shared.txt")"
    assert_equals "added" "$(cat "${dst_dir}/added.txt")"
    assert_equals "keep" "$(cat "${dst_dir}/keep.txt")"
}

test_file_utils_make_symlink_relative_creates_relative_link() {
    local temp_dir
    temp_dir="$(harness_make_temp_dir "file-utils")"
    local target_dir="${temp_dir}/targets"
    local link_dir="${temp_dir}/links/sub"
    mkdir -p "${target_dir}" "${link_dir}"
    printf 'payload\n' > "${target_dir}/data.txt"

    local link_file="${link_dir}/data-link.txt"
    make_symlink_relative "${link_file}" "${target_dir}/data.txt"

    assert_status_code 0 "test -L '${link_file}'"
    assert_equals "../../targets/data.txt" "$(readlink "${link_file}")"
    assert_equals "payload" "$(cat "${link_file}")"
}

test_file_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${FILE_UTILS_SCRIPT}\"; source \"${FILE_UTILS_SCRIPT}\"; normalize_path /tmp >/dev/null'"
}
